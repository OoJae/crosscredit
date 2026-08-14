// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";
import {USCBase} from "../vendored/USCBase.sol";
import {INativeQueryVerifier} from "../vendored/VerifierInterface.sol";
import {CreditProfile, ScoreLib, Tier} from "./ScoreLib.sol";
import {SourceKind, EventSigs} from "./SourceKinds.sol";

/// @title CreditRegistry
/// @author CrossCredit
/// @notice The Attestcoin Smart Contract at the heart of CrossCredit. It rebuilds a borrower's
/// credit reputation on Creditcoin from transactions that Creditcoin's block-prover precompile
/// verified for itself — including **real Ethereum mainnet DeFi history**.
///
/// @dev **Why multi-source matters, and not just for coverage.** An earlier version read only our
/// own `LoanBook` on Sepolia. That contract has no lender: anyone can open a loan with a
/// self-declared principal and repay it to nobody, so a spotless credit history cost a few wei of
/// gas to manufacture. Every proof of that history was cryptographically valid and completely
/// meaningless — a rigorous pipeline delivering worthless data.
///
/// Reading Aave V3 on Ethereum mainnet fixes that by construction. You cannot fake an Aave loan,
/// because Aave's pool is a real counterparty whose capital was genuinely at risk. The
/// verification path is identical; only the source is real. See `docs/THREAT_MODEL.md`.
///
/// **The precompile proves inclusion and continuity — nothing else.** It does not check that a
/// transaction succeeded, which chain it came from, or which contract emitted a log. Those are
/// this contract's job, and every ingest passes the same checks regardless of source:
///
///   1. **Replay guard** (inherited from {USCBase}) — one source transaction, ingested once.
///   2. **`(chainKey, emitter)` must be registered** — strictly stronger than the single-chain
///      check it replaces. Creditcoin attests both Sepolia and Ethereum mainnet, so a log is only
///      trusted when *that* contract on *that* chain is a known source.
///   3. **`receiptStatus == 1`** — the precompile documents that it does not check this.
///   4. **topic0 must match the registered protocol's expected events.**
///   5. Borrower is read from an **indexed topic**, never from a caller-supplied argument, so a
///      worker relaying a proof cannot credit reputation to itself.
contract CreditRegistry is USCBase, Ownable, Pausable {
    /// @notice Declared intent accompanying a proof. Unattested, so validated but never trusted
    /// for routing — dispatch is driven by the log's own emitter and topic0.
    enum Action {
        Generic
    }

    /// @notice Per-loan state reconstructed from proven events (Sepolia `LoanBook` only).
    /// @dev `LoanBook` never emits "closed"; closure is inferred once repayments cover principal.
    struct LoanRecord {
        address borrower;
        uint256 principal;
        uint256 repaid;
        bool closed;
    }

    /// @notice Largest batch the block-prover precompile accepts.
    /// @dev Established by probing the live precompile — ten pass, eleven revert with
    /// `heights: Value is too large for length`. Note batching is only reachable for histories
    /// inside a 1000-block window, which in practice means Sepolia; real mainnet history spans
    /// years and is imported one proof at a time.
    uint256 public constant MAX_BATCH_SIZE = 10;

    /// @notice Registered credit sources, keyed by chain then emitting contract.
    mapping(uint64 => mapping(address => SourceKind)) public sources;

    /// @notice Verified credit profile per borrower.
    mapping(address => CreditProfile) public profiles;

    /// @notice Reconstructed `LoanBook` loan state, keyed by the source chain's loan id.
    mapping(uint256 => LoanRecord) public loans;

    event SourceRegistered(uint64 indexed chainKey, address indexed emitter, SourceKind kind);
    event SourceRemoved(uint64 indexed chainKey, address indexed emitter);
    event HistoryEventIngested(
        address indexed borrower, bytes32 indexed queryId, bytes32 eventSig, uint64 chainKey, uint256 loanId
    );
    event ScoreUpdated(address indexed borrower, uint16 oldScore, uint16 newScore, Tier tier);
    event LoanClosed(address indexed borrower, uint256 indexed loanId);
    event CapacityDemonstrated(address indexed borrower, uint256 amountWei);
    event Liquidated(address indexed borrower, uint64 chainKey);

    error SourceNotRegistered(uint64 chainKey, address emitter);
    error SourceTransactionFailed(uint8 receiptStatus);
    error UnsupportedTransactionType(uint8 txType);
    error NoRecognisedEvents();
    error UnknownAction(uint8 action);
    error ZeroAddress();
    error EmptyBatch();
    error BatchTooLarge(uint256 size, uint256 maximum);
    error BatchLengthMismatch();
    error QueryAlreadyProcessed(bytes32 queryId);

    constructor() Ownable(msg.sender) {}

    // ─── Source administration ────────────────────────────────────────────────────────────

    /// @notice Registers a contract on a source chain as a recognised credit source.
    /// @dev Owner-gated because adding a source is a trust decision — it says "logs shaped like
    /// this, from this address, on this chain, mean something." The proofs remain trustless; what
    /// is curated is only *which real-world protocols count as credit*.
    /// @param chainKey Creditcoin-internal source chain id (1 = Sepolia, 3 = Ethereum mainnet).
    /// @param emitter The contract whose logs are trusted.
    /// @param kind How to decode its events.
    function registerSource(uint64 chainKey, address emitter, SourceKind kind) external onlyOwner {
        if (emitter == address(0)) revert ZeroAddress();
        sources[chainKey][emitter] = kind;
        emit SourceRegistered(chainKey, emitter, kind);
    }

    /// @notice Stops trusting a source. Already-ingested history is unaffected.
    function removeSource(uint64 chainKey, address emitter) external onlyOwner {
        delete sources[chainKey][emitter];
        emit SourceRemoved(chainKey, emitter);
    }

    // ─── Views ────────────────────────────────────────────────────────────────────────────

    function profileOf(address borrower) external view returns (CreditProfile memory) {
        return profiles[borrower];
    }

    /// @notice The borrower's current tier. `LendingPool` reads this to price loans.
    function tierOf(address borrower) external view returns (Tier) {
        CreditProfile memory profile = profiles[borrower];
        return ScoreLib.tierFor(profile, profile.score);
    }

    function scoreOf(address borrower) external view returns (uint16) {
        return profiles[borrower].score;
    }

    /// @notice How much a borrower may borrow **undercollateralized**.
    /// @dev The sybil answer, and it is arithmetic rather than an identity check. Capacity is
    /// anchored to capital that real third parties demonstrably put at risk, so it is invariant
    /// under identity multiplication: splitting one history across a thousand fresh wallets
    /// divides the capacity rather than multiplying it, and a wallet with no mainnet history has
    /// none at all regardless of its score.
    function demonstratedCapacityOf(address borrower) external view returns (uint256) {
        return profiles[borrower].demonstratedCapacityWei;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ─── Ingestion ────────────────────────────────────────────────────────────────────────

    /// @inheritdoc USCBase
    function _processAndEmitEvent(uint8 action, bytes32 queryId, uint64 chainKey, bytes memory encodedTransaction)
        internal
        override
    {
        _ingestTransaction(action, queryId, chainKey, encodedTransaction);
    }

    /// @notice Verifies and applies up to {MAX_BATCH_SIZE} source transactions in one Creditcoin
    /// transaction, sharing a single continuity proof.
    ///
    /// @dev Query ids are reserved **before** verification, inverting {USCBase-execute}'s order.
    /// Safe, because any failure reverts and unwinds the marks. Necessary, because it is the only
    /// thing that catches a duplicate *within* the batch — two copies of one proof would otherwise
    /// both pass an up-front "not yet processed" check. The batch is atomic: one bad proof discards
    /// everything, since a half-imported history is worse than none.
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
        if (actions.length != size || encodedTransactions.length != size || merkleProofs.length != size) {
            revert BatchLengthMismatch();
        }

        bytes32[] memory queryIds = new bytes32[](size);
        for (uint256 i = 0; i < size; ++i) {
            bytes32 queryId = _computeQueryId(chainKey, heights[i], merkleProofs[i].root, merkleProofs[i].siblings);
            if (processedQueries[queryId]) revert QueryAlreadyProcessed(queryId);
            processedQueries[queryId] = true;
            queryIds[i] = queryId;
        }

        bool verified =
            VERIFIER.verifyAndEmit(chainKey, heights, encodedTransactions, merkleProofs, sharedContinuityProof);
        require(verified, "Batch proof verification failed");

        for (uint256 i = 0; i < size; ++i) {
            _ingestTransaction(actions[i], queryIds[i], chainKey, encodedTransactions[i]);
        }

        return true;
    }

    /// @dev The single validation-and-apply path, shared by {USCBase-execute} and {executeBatch},
    /// so both routes enforce identical rules by construction rather than by discipline.
    ///
    /// Every recognised log in the transaction is ingested, not just one. `queryId` derives from
    /// `(chainKey, blockHeight, txIndex)`, so it identifies a **transaction**; routing on the
    /// caller's `action` would consume the id on the first submission and permanently lose any
    /// second credit event in that transaction. A single mainnet transaction routinely touches
    /// several protocols, which makes this essential rather than merely tidy.
    function _ingestTransaction(uint8 action, bytes32 queryId, uint64 chainKey, bytes memory encodedTransaction)
        internal
        whenNotPaused
    {
        if (action > uint8(Action.Generic)) revert UnknownAction(action);

        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        if (!EvmV1Decoder.isValidTransactionType(txType)) revert UnsupportedTransactionType(txType);

        // Decode once and reuse — each call into EvmV1Decoder is a delegatecall that re-encodes
        // the whole payload, and mainnet transactions carry many logs.
        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        if (receipt.receiptStatus != 1) revert SourceTransactionFailed(receipt.receiptStatus);

        uint256 ingested;
        for (uint256 i = 0; i < receipt.receiptLogs.length; ++i) {
            EvmV1Decoder.LogEntry memory log = receipt.receiptLogs[i];
            if (log.topics.length == 0) continue;

            // Source authentication. Topic filtering alone proves nothing about provenance, and a
            // mainnet transaction's logs come from many unrelated contracts.
            SourceKind kind = sources[chainKey][log.address_];
            if (kind == SourceKind.None) continue;

            if (_route(kind, log, queryId, chainKey)) ++ingested;
        }

        if (ingested == 0) revert NoRecognisedEvents();
    }

    /// @dev Dispatches one recognised log to its protocol decoder.
    /// @return handled True when the log matched an event this source kind understands.
    function _route(SourceKind kind, EvmV1Decoder.LogEntry memory log, bytes32 queryId, uint64 chainKey)
        private
        returns (bool handled)
    {
        bytes32 sig = log.topics[0];

        if (kind == SourceKind.LoanBook) {
            if (sig == EventSigs.LOAN_OPENED) return _ingestLoanOpened(log, queryId, chainKey);
            if (sig == EventSigs.REPAYMENT_MADE) return _ingestLoanBookRepayment(log, queryId, chainKey);
            if (sig == EventSigs.COLLATERAL_ADDED) return _ingestCollateral(log, queryId, chainKey);
            return false;
        }

        if (kind == SourceKind.AaveV3) {
            if (sig == EventSigs.AAVE_REPAY) return _ingestAaveRepay(log, queryId, chainKey);
            if (sig == EventSigs.AAVE_LIQUIDATION) return _ingestAaveLiquidation(log, queryId, chainKey);
            // `Borrow` is recognised but scores nothing on its own — borrowing is not
            // creditworthiness, repaying is. It is accepted so a borrow-and-repay pair in one
            // transaction does not fail the "no recognised events" check.
            if (sig == EventSigs.AAVE_BORROW) return true;
            return false;
        }

        if (kind == SourceKind.EnsRegistrar) {
            if (sig == EventSigs.ENS_REGISTERED_V4 || sig == EventSigs.ENS_REGISTERED_V3) {
                return _ingestEnsRegistration(log, queryId, chainKey, sig);
            }
            return false;
        }

        if (kind == SourceKind.ProofOfHumanity) {
            if (sig == EventSigs.POH_UPDATE_INITIATED) return _ingestHumanity(log, queryId, chainKey);
            return false;
        }

        return false;
    }

    // ─── Sepolia LoanBook decoders ────────────────────────────────────────────────────────

    /// @dev `LoanOpened(uint256 indexed loanId, address indexed borrower, uint256 principal, uint64 dueDate)`
    function _ingestLoanOpened(EvmV1Decoder.LogEntry memory log, bytes32 queryId, uint64 chainKey)
        private
        returns (bool)
    {
        if (log.topics.length != 3 || log.data.length != 64) return false;

        uint256 loanId = uint256(log.topics[1]);
        address borrower = _addressFromTopic(log.topics[2]);
        (uint256 principal,) = abi.decode(log.data, (uint256, uint64));

        LoanRecord storage loan = loans[loanId];
        if (loan.principal == 0) {
            loan.borrower = borrower;
            loan.principal = principal;
            profiles[borrower].loansOpened += 1;
        }

        _touch(borrower, 0);
        emit HistoryEventIngested(borrower, queryId, EventSigs.LOAN_OPENED, chainKey, loanId);

        // Repayments may have been proven before this opening — each proof is independent, so
        // events can arrive in any order. Re-check closure now the principal is known.
        _reconcile(loanId);
        _refreshScore(borrower);
        return true;
    }

    /// @dev `RepaymentMade(uint256 indexed loanId, address indexed borrower, uint256 amount, bool onTime, uint64 timestamp)`
    function _ingestLoanBookRepayment(EvmV1Decoder.LogEntry memory log, bytes32 queryId, uint64 chainKey)
        private
        returns (bool)
    {
        if (log.topics.length != 3 || log.data.length != 96) return false;

        uint256 loanId = uint256(log.topics[1]);
        address borrower = _addressFromTopic(log.topics[2]);
        (uint256 amount, bool onTime, uint64 timestamp) = abi.decode(log.data, (uint256, bool, uint64));

        CreditProfile storage profile = profiles[borrower];
        profile.totalRepaidWei += amount;
        // `onTime` is decided by the source chain's own clock and carried in the proven log;
        // Creditcoin cannot re-derive it. This is exactly the field that does not exist on real
        // mainnet lending protocols, which is why they are scored on liquidations instead.
        if (onTime) profile.onTime += 1;
        else profile.late += 1;

        LoanRecord storage loan = loans[loanId];
        if (loan.borrower == address(0)) loan.borrower = borrower;
        loan.repaid += amount;

        _touch(borrower, timestamp);
        emit HistoryEventIngested(borrower, queryId, EventSigs.REPAYMENT_MADE, chainKey, loanId);

        _reconcile(loanId);
        _refreshScore(borrower);
        return true;
    }

    /// @dev `CollateralAdded(address indexed borrower, uint256 amount)`
    function _ingestCollateral(EvmV1Decoder.LogEntry memory log, bytes32 queryId, uint64 chainKey)
        private
        returns (bool)
    {
        if (log.topics.length != 2 || log.data.length != 32) return false;

        address borrower = _addressFromTopic(log.topics[1]);
        profiles[borrower].totalCollateralWei += abi.decode(log.data, (uint256));

        _touch(borrower, 0);
        emit HistoryEventIngested(borrower, queryId, EventSigs.COLLATERAL_ADDED, chainKey, 0);
        _refreshScore(borrower);
        return true;
    }

    // ─── Ethereum mainnet decoders ────────────────────────────────────────────────────────

    /// @dev `Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount, bool useATokens)`
    ///
    /// The signal that actually matters. There is no due date and therefore no `onTime` — Aave
    /// positions are perpetual — so what this proves is narrower and stronger: a real protocol
    /// had capital at risk against this address, and this address gave it back. That is the only
    /// evidence in the system that costs an attacker real money to produce, so it is the only
    /// evidence that raises {CreditProfile-demonstratedCapacityWei}, which caps undercollateralized
    /// borrowing.
    function _ingestAaveRepay(EvmV1Decoder.LogEntry memory log, bytes32 queryId, uint64 chainKey)
        private
        returns (bool)
    {
        if (log.topics.length != 4 || log.data.length != 64) return false;

        address borrower = _addressFromTopic(log.topics[2]);
        (uint256 amount,) = abi.decode(log.data, (uint256, bool));

        CreditProfile storage profile = profiles[borrower];
        profile.mainnetRepayments += 1;
        profile.totalRepaidWei += amount;
        // Capacity is the largest single repayment, not the sum: repaying 1 ETH a hundred times
        // demonstrates the ability to handle 1 ETH, not 100.
        if (amount > profile.demonstratedCapacityWei) {
            profile.demonstratedCapacityWei = amount;
            emit CapacityDemonstrated(borrower, amount);
        }

        _touch(borrower, 0);
        emit HistoryEventIngested(borrower, queryId, EventSigs.AAVE_REPAY, chainKey, 0);
        _refreshScore(borrower);
        return true;
    }

    /// @dev `LiquidationCall(address indexed collateralAsset, address indexed debtAsset, address indexed user, ...)`
    ///
    /// The mainnet analogue of a default. Rare enough to be high-signal — roughly one per 9,500
    /// blocks across all of Aave V3 — so a long borrowing record with none is meaningful, and a
    /// single one bars Platinum outright.
    function _ingestAaveLiquidation(EvmV1Decoder.LogEntry memory log, bytes32 queryId, uint64 chainKey)
        private
        returns (bool)
    {
        if (log.topics.length != 4) return false;

        address borrower = _addressFromTopic(log.topics[3]);
        profiles[borrower].liquidations += 1;

        _touch(borrower, 0);
        emit Liquidated(borrower, chainKey);
        emit HistoryEventIngested(borrower, queryId, EventSigs.AAVE_LIQUIDATION, chainKey, 0);
        _refreshScore(borrower);
        return true;
    }

    /// @dev `NameRegistered(... bytes32 indexed labelhash, address indexed owner, ... uint256 expires ...)`
    ///
    /// Not credit — a sunk cost with a provable expiry, worth roughly $25 for five years. A rate
    /// limiter on cheap identity creation, never a licence to borrow. The expiry is enforced
    /// against Creditcoin's clock so a lapsed name cannot be replayed as a current one.
    function _ingestEnsRegistration(
        EvmV1Decoder.LogEntry memory log,
        bytes32 queryId,
        uint64 chainKey,
        bytes32 sig
    ) private returns (bool) {
        if (log.topics.length != 3) return false;

        address owner = _addressFromTopic(log.topics[2]);
        uint256 expires = _ensExpiry(log.data, sig);
        if (expires <= block.timestamp) return false;

        CreditProfile storage profile = profiles[owner];
        if (uint64(expires) > profile.identityExpiry) profile.identityExpiry = uint64(expires);

        _touch(owner, 0);
        emit HistoryEventIngested(owner, queryId, sig, chainKey, 0);
        _refreshScore(owner);
        return true;
    }

    /// @dev `UpdateInitiated(bytes20 indexed humanityId, address indexed owner, uint40 expirationTime, bool claimed, address gateway)`
    ///
    /// Implemented, and it verifies — but see `docs/THREAT_MODEL.md`: mainnet Proof of Humanity
    /// holds 55 humanities, because the real population lives on Gnosis, which Creditcoin does not
    /// attest. It is here because it is the only mainnet personhood event carrying both an address
    /// and a self-describing expiry, not because it is load-bearing.
    function _ingestHumanity(EvmV1Decoder.LogEntry memory log, bytes32 queryId, uint64 chainKey)
        private
        returns (bool)
    {
        if (log.topics.length != 3 || log.data.length < 96) return false;

        address owner = _addressFromTopic(log.topics[2]);
        (uint256 expirationTime, bool claimed,) = abi.decode(log.data, (uint256, bool, address));
        if (!claimed || expirationTime <= block.timestamp) return false;

        CreditProfile storage profile = profiles[owner];
        if (uint64(expirationTime) > profile.identityExpiry) profile.identityExpiry = uint64(expirationTime);

        _touch(owner, 0);
        emit HistoryEventIngested(owner, queryId, EventSigs.POH_UPDATE_INITIATED, chainKey, 0);
        _refreshScore(owner);
        return true;
    }

    // ─── Internals ────────────────────────────────────────────────────────────────────────

    /// @dev ENS controller versions differ in their non-indexed layout. v4 is
    /// `(string label, uint256 baseCost, uint256 premium, uint256 expires, bytes32 referrer)`;
    /// v2/v3 are `(string name, uint256 cost, uint256 expires)`. Returns 0 when the layout does
    /// not decode, so a malformed log is ignored rather than trusted.
    function _ensExpiry(bytes memory data, bytes32 sig) private pure returns (uint256) {
        if (sig == EventSigs.ENS_REGISTERED_V4) {
            (, , , uint256 expires, ) = abi.decode(data, (string, uint256, uint256, uint256, bytes32));
            return expires;
        }
        (, , uint256 expiresV3) = abi.decode(data, (string, uint256, uint256));
        return expiresV3;
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

    /// @dev Records first contact and, where the source gives one, the earliest source-chain
    /// timestamp seen. That timestamp is the score's time axis — the one input a scripted
    /// attacker cannot compress.
    function _touch(address borrower, uint64 sourceTimestamp) private {
        CreditProfile storage profile = profiles[borrower];
        if (profile.firstSeen == 0) profile.firstSeen = uint64(block.timestamp);

        // Fall back to now when the source carries no timestamp; a later, older proof will
        // correct it downward, which only ever helps the borrower and cannot be gamed upward.
        uint64 observed = sourceTimestamp == 0 ? uint64(block.timestamp) : sourceTimestamp;
        if (profile.oldestActivity == 0 || observed < profile.oldestActivity) {
            profile.oldestActivity = observed;
        }
    }

    function _refreshScore(address borrower) private {
        CreditProfile storage stored = profiles[borrower];
        uint16 oldScore = stored.score;

        CreditProfile memory snapshot = stored;
        uint16 newScore = ScoreLib.compute(snapshot, uint64(block.timestamp));
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
