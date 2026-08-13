// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";
import {USCBase} from "../vendored/USCBase.sol";
import {INativeQueryVerifier} from "../vendored/VerifierInterface.sol";
import {CreditProfile, ScoreLib, Tier} from "./ScoreLib.sol";

/// @title CreditRegistry
/// @author CrossCredit
/// @notice The Attestcoin Smart Contract at the heart of CrossCredit. It rebuilds a borrower's
/// credit reputation on Creditcoin purely from Ethereum Sepolia transactions that Creditcoin's
/// block-prover precompile verified for itself — no oracle operator, no bridge multisig, no
/// trusted relayer.
///
/// @dev **The precompile proving "this transaction happened" is the beginning of the security
/// argument, not the end.** A genuine proof of a genuine transaction is still worthless if it
/// came from the wrong chain, the wrong contract, or a call that reverted. Every ingest therefore
/// passes five independent checks before a single point of score moves:
///
///   1. **Replay guard** (inherited from {USCBase}) — one source transaction, ingested once.
///   2. **`chainKey == SOURCE_CHAIN_KEY`** — CC3 attests *two* source chains (Sepolia is key 1,
///      Ethereum Mainnet is key 3). Without this, a contract deployed at the same address on
///      mainnet could emit look-alike events and have them accepted as Sepolia history.
///   3. **`receiptStatus == 1`** — the precompile documents that it does *not* check transaction
///      success. A reverted repayment is still "included in a block". We check it ourselves.
///   4. **Emitter is `LOANBOOK`** — `getLogsByEventSignature` filters on topic0 alone, so without
///      this anyone could deploy a contract emitting identically-shaped events and mint history.
///   5. **topic0 is a known LoanBook event** — dispatch is driven by the log itself.
///
/// Note what is *absent*: nowhere does this contract trust a caller-supplied borrower address.
/// The borrower is read from the log's indexed topic, so the worker relaying a proof cannot
/// credit reputation to itself.
contract CreditRegistry is USCBase, Ownable, Pausable {
    using ScoreLib for CreditProfile;

    /// @notice Declared intent accompanying a proof. See {_processAndEmitEvent} for why this is
    /// treated as a hint rather than as routing.
    enum Action {
        LoanOpened,
        RepaymentMade,
        CollateralAdded
    }

    /// @dev topic0 of `LoanOpened(uint256,address,uint256,uint64)`.
    bytes32 public constant LOAN_OPENED_SIG = 0x0d7f8e19afd65be70c0b9ff46dab1702a44ca0e8fcd33448375d7c2690e5866b;
    /// @dev topic0 of `RepaymentMade(uint256,address,uint256,bool,uint64)`.
    bytes32 public constant REPAYMENT_MADE_SIG = 0x7d64aa0e099ec7ce5a5e95941014b245cf86dd8cd1115dd1ee421d8ec4d04206;
    /// @dev topic0 of `CollateralAdded(address,uint256)`.
    bytes32 public constant COLLATERAL_ADDED_SIG = 0x7dba1be544024070cd5eebfa8bdd80a8b198cea8058c7d3cc1f8dd36e41ab2f7;

    /// @notice Per-loan state reconstructed from proven events.
    /// @dev Kept so loan closure can be derived without trusting anyone to assert it. `LoanBook`
    /// never emits "closed" — we infer it once cumulative repayments reach the principal.
    struct LoanRecord {
        address borrower;
        uint256 principal;
        uint256 repaid;
        bool closed;
    }

    /// @notice The Creditcoin-internal id of the source chain we accept proofs from.
    uint64 public immutable SOURCE_CHAIN_KEY;

    /// @notice The Sepolia `LoanBook` whose events constitute valid credit history.
    address public immutable LOANBOOK;

    /// @notice Verified credit profile per borrower.
    mapping(address => CreditProfile) public profiles;

    /// @notice Reconstructed loan state, keyed by the source chain's loan id.
    mapping(uint256 => LoanRecord) public loans;

    /// @notice Emitted once per credit event successfully ingested from a verified transaction.
    event HistoryEventIngested(address indexed borrower, bytes32 indexed queryId, bytes32 eventSig, uint256 loanId);

    /// @notice Emitted whenever a borrower's score changes.
    event ScoreUpdated(address indexed borrower, uint16 oldScore, uint16 newScore, Tier tier);

    /// @notice Emitted when a loan's cumulative repayments reach its principal.
    event LoanClosed(address indexed borrower, uint256 indexed loanId);

    error WrongSourceChain(uint64 expected, uint64 received);
    error SourceTransactionFailed(uint8 receiptStatus);
    error UnsupportedTransactionType(uint8 txType);
    error NoRecognisedEvents();
    error UnknownAction(uint8 action);
    error ZeroAddress();
    error EmptyBatch();
    error BatchTooLarge(uint256 size, uint256 maximum);
    error BatchLengthMismatch();
    error QueryAlreadyProcessed(bytes32 queryId);

    /// @notice Largest batch the block-prover precompile accepts.
    /// @dev Not a documented constant in the SDK — confirmed by probing the live CC3 precompile:
    /// ten proofs pass the size gate, eleven revert with `heights: Value is too large for length`.
    /// Enforced here so an oversized batch fails with a clear error before spending gas on the
    /// precompile call.
    uint256 public constant MAX_BATCH_SIZE = 10;

    /// @param sourceChainKey Creditcoin-internal source-chain id — 1 for Sepolia on CC3 testnet.
    /// Taken from `docs/evidence/supported-chains.json`, never hardcoded, because the same key
    /// denotes a different chain on mainnet.
    /// @param loanBook Address of the Sepolia `LoanBook`.
    constructor(uint64 sourceChainKey, address loanBook) Ownable(msg.sender) {
        if (loanBook == address(0)) revert ZeroAddress();
        SOURCE_CHAIN_KEY = sourceChainKey;
        LOANBOOK = loanBook;
    }

    /// @notice Returns a borrower's full verified profile.
    function profileOf(address borrower) external view returns (CreditProfile memory) {
        return profiles[borrower];
    }

    /// @notice Returns a borrower's current tier. `LendingPool` reads this to price loans.
    /// @dev A pull, not a push: the verification hot path never calls out to other contracts.
    function tierOf(address borrower) external view returns (Tier) {
        CreditProfile memory profile = profiles[borrower];
        return ScoreLib.tierFor(profile, profile.score);
    }

    /// @notice Returns a borrower's current score.
    function scoreOf(address borrower) external view returns (uint16) {
        return profiles[borrower].score;
    }

    /// @notice Halts ingestion. Verification is irreversible once applied, so an operator needs a
    /// stop button if a source-chain issue is discovered mid-flight.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resumes ingestion.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Applies a verified Sepolia transaction to the credit graph.
    /// @dev Invoked by {USCBase-execute} only after the precompile confirmed inclusion and
    /// continuity and the replay guard consumed `queryId`.
    ///
    /// **Every recognised LoanBook log in the transaction is ingested, not just the one matching
    /// `action`.** This deliberately departs from the Gluwa examples, which process only the first
    /// log of the requested type. `queryId` is derived from `(chainKey, blockHeight, txIndex)`, so
    /// it identifies a *transaction*, not an event — meaning a transaction emitting two credit
    /// events could only ever be submitted once, and action-based routing would silently discard
    /// the second one forever. Ingesting the whole transaction makes one queryId correspond
    /// exactly to "all credit events in that transaction", which is both complete and still
    /// perfectly replay-protected.
    ///
    /// `action` is therefore validated as a known enum member and otherwise unused: it arrives
    /// from the caller and is *not* covered by the proof, so routing on it would mean trusting
    /// unattested data.
    function _processAndEmitEvent(uint8 action, bytes32 queryId, uint64 chainKey, bytes memory encodedTransaction)
        internal
        override
    {
        _ingestTransaction(action, queryId, chainKey, encodedTransaction);
    }

    /// @notice Verifies and applies up to {MAX_BATCH_SIZE} source transactions in **one**
    /// Creditcoin transaction, sharing a single continuity proof.
    ///
    /// @dev This is what makes "import my entire credit history in one transaction" possible, and
    /// it is our own entrypoint: the vendored {USCBase-execute} handles exactly one proof.
    ///
    /// Sharing one continuity proof across the batch is where the saving comes from — the
    /// expensive part of verification is walking the chain back to an attested block, and that
    /// walk happens once instead of N times. The precompile requires every source block to fall
    /// within a 1000-block window for that to be sound.
    ///
    /// **Query ids are reserved before verification, not after.** {USCBase-execute} marks after
    /// verifying so a rejected proof cannot burn a legitimate id; here, marking first is both safe
    /// and necessary. Safe because any failure reverts the whole transaction and unwinds the
    /// marks. Necessary because it is the only thing that catches a **duplicate inside the same
    /// batch** — two copies of one proof would otherwise both pass a "not yet processed" check and
    /// be counted twice.
    ///
    /// The batch is atomic: one bad proof, one replay, or one unrecognised event reverts
    /// everything. A partially-applied credit history would be worse than none.
    ///
    /// @param actions Declared intent per item. Unattested, so validated but never used for routing.
    /// @param chainKey Source chain for every item in the batch.
    /// @param heights Source block per item, index-aligned with the other arrays.
    /// @param encodedTransactions Attestcoin-encoded transaction + receipt per item.
    /// @param merkleProofs Inclusion proof per item.
    /// @param sharedContinuityProof The single continuity proof covering all of them.
    /// @return True when every item verified and was applied.
    function executeBatch(
        uint8[] calldata actions,
        uint64 chainKey,
        uint64[] calldata heights,
        bytes[] calldata encodedTransactions,
        INativeQueryVerifier.MerkleProof[] calldata merkleProofs,
        INativeQueryVerifier.ContinuityProof calldata sharedContinuityProof
    ) external returns (bool) {
        uint256 size = heights.length;
        if (size == 0) revert EmptyBatch();
        if (size > MAX_BATCH_SIZE) revert BatchTooLarge(size, MAX_BATCH_SIZE);
        if (
            actions.length != size || encodedTransactions.length != size || merkleProofs.length != size
        ) revert BatchLengthMismatch();

        bytes32[] memory queryIds = new bytes32[](size);
        for (uint256 i = 0; i < size; ++i) {
            bytes32 queryId =
                _computeQueryId(chainKey, heights[i], merkleProofs[i].root, merkleProofs[i].siblings);
            if (processedQueries[queryId]) revert QueryAlreadyProcessed(queryId);
            processedQueries[queryId] = true;
            queryIds[i] = queryId;
        }

        // One precompile call for the whole batch. It reverts on any failure rather than
        // returning false, so a successful return means every proof checked out.
        bool verified = VERIFIER.verifyAndEmit(
            chainKey, heights, encodedTransactions, merkleProofs, sharedContinuityProof
        );
        require(verified, "Batch proof verification failed");

        for (uint256 i = 0; i < size; ++i) {
            _ingestTransaction(actions[i], queryIds[i], chainKey, encodedTransactions[i]);
        }

        return true;
    }

    /// @dev The single validation-and-apply path, shared by {USCBase-execute} and
    /// {executeBatch}, so both routes enforce identical rules by construction rather than by
    /// discipline.
    function _ingestTransaction(uint8 action, bytes32 queryId, uint64 chainKey, bytes memory encodedTransaction)
        internal
        whenNotPaused
    {
        if (action > uint8(Action.CollateralAdded)) revert UnknownAction(action);
        if (chainKey != SOURCE_CHAIN_KEY) revert WrongSourceChain(SOURCE_CHAIN_KEY, chainKey);

        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        if (!EvmV1Decoder.isValidTransactionType(txType)) revert UnsupportedTransactionType(txType);

        // Decode once and reuse — each call into EvmV1Decoder is a delegatecall that re-encodes
        // the entire payload, so re-decoding is genuinely expensive.
        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        if (receipt.receiptStatus != 1) revert SourceTransactionFailed(receipt.receiptStatus);

        uint256 ingested;
        for (uint256 i = 0; i < receipt.receiptLogs.length; ++i) {
            EvmV1Decoder.LogEntry memory log = receipt.receiptLogs[i];

            // Source authentication. Topic filtering alone proves nothing about provenance.
            if (log.address_ != LOANBOOK) continue;
            if (log.topics.length == 0) continue;

            bytes32 sig = log.topics[0];
            if (sig == LOAN_OPENED_SIG) {
                _ingestLoanOpened(log, queryId);
            } else if (sig == REPAYMENT_MADE_SIG) {
                _ingestRepayment(log, queryId);
            } else if (sig == COLLATERAL_ADDED_SIG) {
                _ingestCollateral(log, queryId);
            } else {
                continue;
            }
            ++ingested;
        }

        if (ingested == 0) revert NoRecognisedEvents();
    }

    /// @dev `LoanOpened(uint256 indexed loanId, address indexed borrower, uint256 principal, uint64 dueDate)`.
    function _ingestLoanOpened(EvmV1Decoder.LogEntry memory log, bytes32 queryId) private {
        if (log.topics.length != 3 || log.data.length != 64) revert NoRecognisedEvents();

        uint256 loanId = uint256(log.topics[1]);
        address borrower = _addressFromTopic(log.topics[2]);
        (uint256 principal,) = abi.decode(log.data, (uint256, uint64));

        LoanRecord storage loan = loans[loanId];
        if (loan.principal == 0) {
            loan.borrower = borrower;
            loan.principal = principal;
            profiles[borrower].loansOpened += 1;
        }

        _touch(borrower);
        emit HistoryEventIngested(borrower, queryId, LOAN_OPENED_SIG, loanId);

        // Repayments may have been proven before this opening — events can arrive in any order,
        // since each is an independent proof. Re-check closure now that the principal is known.
        _reconcile(loanId);
        _refreshScore(borrower);
    }

    /// @dev `RepaymentMade(uint256 indexed loanId, address indexed borrower, uint256 amount, bool onTime, uint64 timestamp)`.
    function _ingestRepayment(EvmV1Decoder.LogEntry memory log, bytes32 queryId) private {
        if (log.topics.length != 3 || log.data.length != 96) revert NoRecognisedEvents();

        uint256 loanId = uint256(log.topics[1]);
        address borrower = _addressFromTopic(log.topics[2]);
        (uint256 amount, bool onTime,) = abi.decode(log.data, (uint256, bool, uint64));

        CreditProfile storage profile = profiles[borrower];
        profile.totalRepaidWei += amount;
        // `onTime` is decided by the source chain's own clock and carried in the proven log.
        // Creditcoin has no way to re-derive it, which is precisely why LoanBook stamps it.
        if (onTime) {
            profile.onTime += 1;
        } else {
            profile.late += 1;
        }

        LoanRecord storage loan = loans[loanId];
        if (loan.borrower == address(0)) loan.borrower = borrower;
        loan.repaid += amount;

        _touch(borrower);
        emit HistoryEventIngested(borrower, queryId, REPAYMENT_MADE_SIG, loanId);

        _reconcile(loanId);
        _refreshScore(borrower);
    }

    /// @dev `CollateralAdded(address indexed borrower, uint256 amount)`.
    function _ingestCollateral(EvmV1Decoder.LogEntry memory log, bytes32 queryId) private {
        if (log.topics.length != 2 || log.data.length != 32) revert NoRecognisedEvents();

        address borrower = _addressFromTopic(log.topics[1]);
        uint256 amount = abi.decode(log.data, (uint256));

        profiles[borrower].totalCollateralWei += amount;

        _touch(borrower);
        emit HistoryEventIngested(borrower, queryId, COLLATERAL_ADDED_SIG, 0);
        _refreshScore(borrower);
    }

    /// @dev Marks a loan closed once proven repayments cover its principal. Idempotent, and safe
    /// whichever order the proofs arrive in.
    function _reconcile(uint256 loanId) private {
        LoanRecord storage loan = loans[loanId];
        if (loan.closed || loan.principal == 0 || loan.repaid < loan.principal) return;

        loan.closed = true;
        profiles[loan.borrower].loansClosed += 1;
        emit LoanClosed(loan.borrower, loanId);
    }

    /// @dev Records first contact, so longevity can be scored once histories are old enough to
    /// make that meaningful.
    function _touch(address borrower) private {
        CreditProfile storage profile = profiles[borrower];
        if (profile.firstSeen == 0) profile.firstSeen = uint64(block.timestamp);
    }

    function _refreshScore(address borrower) private {
        CreditProfile storage stored = profiles[borrower];
        uint16 oldScore = stored.score;

        CreditProfile memory snapshot = stored;
        uint16 newScore = ScoreLib.compute(snapshot);
        if (newScore == oldScore) return;

        stored.score = newScore;
        snapshot.score = newScore;
        emit ScoreUpdated(borrower, oldScore, newScore, ScoreLib.tierFor(snapshot, newScore));
    }

    /// @dev An indexed `address` occupies the low 20 bytes of its topic.
    function _addressFromTopic(bytes32 topic) private pure returns (address) {
        return address(uint160(uint256(topic)));
    }
}
