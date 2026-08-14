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

    /// @notice Decimals for reserve assets whose repayments count toward demonstrated capacity.
    /// @dev Aave denominates `Repay` amounts in the **reserve asset's own units** — USDC has 6
    /// decimals, WBTC 8, WETH 18 — so a raw amount is meaningless without knowing which asset it
    /// is. Decimals live in contract *state* on the source chain, and the precompile proves
    /// transactions rather than state, so they cannot be read cross-chain and must be registered.
    ///
    /// A repayment naming an unregistered reserve is **rejected outright** rather than ingested
    /// for zero capacity. Silently crediting nothing looked like failing closed but was worse than
    /// either alternative: it consumed the transaction's `queryId` permanently, so the proof could
    /// never be resubmitted once the owner registered the asset, and the borrower's largest
    /// repayment was destroyed rather than deferred. Anyone could have front-run a victim's own
    /// import to cap their capacity at zero forever. Failing loud leaves the proof retryable.
    mapping(address => uint8) public reserveDecimals;

    /// @notice Height-to-time anchors per source chain. See {registerChainAnchor}.
    mapping(uint64 => ChainAnchor) public chainAnchors;

    /// @notice Verified credit profile per borrower.
    mapping(address => CreditProfile) public profiles;

    /// @notice Reconstructed `LoanBook` loan state.
    /// @dev Keyed by `keccak256(chainKey, emitter, loanId)`, not by the bare loan id. Loan ids are
    /// small integers assigned per-contract, so two `LoanBook` deployments — or the same one on two
    /// attested chains — both mint a loan `1`, and a bare key would let one borrower's repayment
    /// close another's loan.
    mapping(bytes32 => LoanRecord) public loans;

    /// @notice A source chain's block-height-to-time reference.
    /// @param height A known block height.
    /// @param timestamp That block's Unix timestamp.
    /// @param secondsPerBlock Average block time used to extrapolate.
    struct ChainAnchor {
        uint64 height;
        uint64 timestamp;
        uint32 secondsPerBlock;
    }

    event SourceRegistered(uint64 indexed chainKey, address indexed emitter, SourceKind kind);
    event ReserveRegistered(address indexed reserve, uint8 decimals);
    event SourceRemoved(uint64 indexed chainKey, address indexed emitter);
    event ChainAnchorRegistered(uint64 indexed chainKey, uint64 height, uint64 timestamp, uint32 secondsPerBlock);
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
    error UnregisteredReserve(address reserve);
    error InvalidAnchor();

    /// @notice Everything a decoder needs about the transaction it is decoding a log out of.
    ///
    /// @dev Passed by reference through {_route} into each decoder, replacing what used to be a
    /// growing tail of `(queryId, chainKey, …)` parameters. Two of its fields are
    /// **transaction-scoped rules** that cannot be expressed per-log, which is the whole reason the
    /// struct exists rather than more parameters:
    ///
    /// - `sawSelfFundedBorrow` — set by a pre-scan when the same transaction contains the Aave
    ///   `Borrow` that funded the `Repay`. That pairing is the signature of a flash loan.
    /// - `repaymentCounted` — mutated during the loop so a transaction contributes at most one
    ///   `mainnetRepayments` increment however many `Repay` logs it carries.
    ///
    /// It also keeps the stack shallow. `via_ir = false` in `foundry.toml`, and threading two more
    /// value parameters through six decoders overflows the 16-slot stack.
    struct IngestContext {
        bytes32 queryId;
        uint64 chainKey;
        uint64 blockHeight;
        bool sawSelfFundedBorrow;
        bool repaymentCounted;
    }

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

    /// @notice Declares the decimals of a reserve asset so repayments of it can be normalised.
    /// @dev Without this, a 789 USDC repayment (789e6) and a 5 ETH repayment (5e18) would be
    /// compared as raw integers and the USDC one would round to nothing.
    /// @param reserve The ERC-20 on the source chain.
    /// @param decimals Its decimals — 6 for USDC/USDT, 8 for WBTC, 18 for WETH/DAI.
    function registerReserve(address reserve, uint8 decimals) external onlyOwner {
        if (reserve == address(0)) revert ZeroAddress();
        reserveDecimals[reserve] = decimals;
        emit ReserveRegistered(reserve, decimals);
    }

    /// @notice Anchors a source chain's block height to wall-clock time, so proven history can be
    /// dated.
    ///
    /// @dev The score's age term needs to know *when* a proven event happened on its own chain.
    /// Almost nothing tells us: Aave, ENS and Proof of Humanity emit no timestamp, and
    /// `EvmV1Decoder` exposes transaction and receipt fields but never a block header. The one
    /// thing we do have is `blockHeight`, which is covered by the Merkle proof and therefore
    /// cannot be forged by whoever submits it.
    ///
    /// So we convert height to time against an owner-registered anchor. That is an approximation
    /// and a trusted input, and both facts are disclosed in `docs/THREAT_MODEL.md` — but it is an
    /// approximation of something real, which beats the alternative it replaces: before this, six
    /// of the seven ingest paths stamped `block.timestamp`, so the age term measured *time since
    /// import*. That rewarded importing early and idling, and gave a decade of genuine Aave
    /// history exactly zero age points — inverting the incentive the term exists to create.
    ///
    /// Post-merge Ethereum is a good citizen here: 12s slots make the linear estimate accurate to
    /// well under the 30-day granularity the age term actually scores in.
    ///
    /// @param chainKey Source chain the anchor applies to.
    /// @param height A known block height on that chain.
    /// @param timestamp That block's Unix timestamp.
    /// @param secondsPerBlock Average block time used to extrapolate from the anchor.
    function registerChainAnchor(uint64 chainKey, uint64 height, uint64 timestamp, uint32 secondsPerBlock)
        external
        onlyOwner
    {
        if (timestamp == 0 || secondsPerBlock == 0) revert InvalidAnchor();
        chainAnchors[chainKey] = ChainAnchor(height, timestamp, secondsPerBlock);
        emit ChainAnchorRegistered(chainKey, height, timestamp, secondsPerBlock);
    }

    // ─── Views ────────────────────────────────────────────────────────────────────────────

    function profileOf(address borrower) external view returns (CreditProfile memory) {
        return profiles[borrower];
    }

    /// @notice The borrower's current tier. `LendingPool` reads this to price loans.
    /// @dev Recomputed live rather than read from the cache — see {scoreOf}.
    function tierOf(address borrower) external view returns (Tier) {
        CreditProfile memory profile = profiles[borrower];
        return ScoreLib.tierFor(profile, ScoreLib.compute(profile, uint64(block.timestamp)));
    }

    /// @notice The borrower's current score.
    ///
    /// @dev Recomputed on read. The stored `profile.score` is a cache refreshed only on ingest,
    /// which makes it stale with respect to *time* — and two of the score's terms are functions of
    /// time. An ENS name could lapse and the cached score would keep paying its identity bonus
    /// forever; a borrower's history could age a year and earn nothing until they happened to
    /// import something. `ScoreLib.compute` is `pure` and already takes `nowTimestamp` for exactly
    /// this reason, so the live read costs nothing but arithmetic.
    ///
    /// The stored value survives as an event and indexing artifact, so `ScoreUpdated` still
    /// reports the ingest-time delta.
    function scoreOf(address borrower) external view returns (uint16) {
        return ScoreLib.compute(profiles[borrower], uint64(block.timestamp));
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

    /// @notice The replay-protection id a given proof would consume.
    /// @dev Exposed because the id is derived from `(chainKey, blockHeight, txIndex)` inside the
    /// base contract, so off-chain callers otherwise have to re-implement the derivation to answer
    /// "have I already imported this?". Pairs with {previewIngest} and with `processedQueries`.
    function queryIdFor(
        uint64 chainKey,
        uint64 blockHeight,
        bytes32 merkleRoot,
        INativeQueryVerifier.MerkleProofEntry[] calldata siblings
    ) external view returns (bytes32) {
        return _computeQueryId(chainKey, blockHeight, merkleRoot, siblings);
    }

    /// @notice Checks a proof and reports what ingesting it would do — without spending anything.
    ///
    /// @dev Uses the precompile's **`verify`** overload, the read-only sibling of the
    /// `verifyAndEmit` every ingest path calls. Official examples only ever use the emitting one,
    /// so this entry point sits unused in most integrations; as a `view` it costs the caller
    /// nothing over RPC, which makes it the natural front door for a UI.
    ///
    /// The value is in what it prevents. Every guard in this contract reverts, and a revert is
    /// indistinguishable from the next one to a user staring at a failed wallet popup: an
    /// unregistered reserve, a replayed query and a look-alike emitter all look like "transaction
    /// failed". This answers *which*, before a signature is requested.
    ///
    /// Note `verify` reverts on a bad proof rather than returning false — the boolean is always
    /// true when you receive it — so a failing proof surfaces as this call reverting with the
    /// precompile's own reason, which is exactly the diagnostic worth showing.
    ///
    /// @return recognised How many logs would be ingested. Zero means the ingest would revert with
    /// `NoRecognisedEvents`.
    /// @return alreadyProcessed True when this transaction's proof has already been consumed.
    /// @return selfFundedBorrow True when a same-transaction Aave borrow would suppress capacity.
    function previewIngest(
        uint64 chainKey,
        uint64 blockHeight,
        bytes calldata encodedTransaction,
        INativeQueryVerifier.MerkleProof calldata merkleProof,
        INativeQueryVerifier.ContinuityProof calldata continuityProof
    ) external view returns (uint256 recognised, bool alreadyProcessed, bool selfFundedBorrow) {
        VERIFIER.verify(chainKey, blockHeight, encodedTransaction, merkleProof, continuityProof);

        bytes32 queryId = _computeQueryId(chainKey, blockHeight, merkleProof.root, merkleProof.siblings);
        alreadyProcessed = processedQueries[queryId];

        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        if (receipt.receiptStatus != 1) return (0, alreadyProcessed, false);

        selfFundedBorrow = _hasSelfFundedBorrow(receipt, chainKey);

        for (uint256 i = 0; i < receipt.receiptLogs.length; ++i) {
            EvmV1Decoder.LogEntry memory log = receipt.receiptLogs[i];
            if (log.topics.length == 0) continue;
            if (sources[chainKey][log.address_] == SourceKind.None) continue;
            if (_isRecognisedSignature(sources[chainKey][log.address_], log.topics[0])) ++recognised;
        }
    }

    /// @dev Pure mirror of {_route}'s signature matching, for {previewIngest}. Kept adjacent to
    /// `_route` deliberately: if one gains a signature and the other does not, the preview lies.
    function _isRecognisedSignature(SourceKind kind, bytes32 sig) private pure returns (bool) {
        if (kind == SourceKind.LoanBook) {
            return sig == EventSigs.LOAN_OPENED || sig == EventSigs.REPAYMENT_MADE
                || sig == EventSigs.COLLATERAL_ADDED;
        }
        if (kind == SourceKind.AaveV3) {
            return sig == EventSigs.AAVE_REPAY || sig == EventSigs.AAVE_LIQUIDATION || sig == EventSigs.AAVE_BORROW;
        }
        if (kind == SourceKind.EnsRegistrar) {
            return sig == EventSigs.ENS_REGISTERED_V4 || sig == EventSigs.ENS_REGISTERED_V3;
        }
        if (kind == SourceKind.ProofOfHumanity) return sig == EventSigs.POH_UPDATE_INITIATED;
        return false;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ─── Ingestion ────────────────────────────────────────────────────────────────────────

    /// @inheritdoc USCBase
    function _processAndEmitEvent(
        uint8 action,
        bytes32 queryId,
        uint64 chainKey,
        uint64 blockHeight,
        bytes memory encodedTransaction
    ) internal override {
        _ingestTransaction(action, queryId, chainKey, blockHeight, encodedTransaction);
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
            _ingestTransaction(actions[i], queryIds[i], chainKey, heights[i], encodedTransactions[i]);
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
    function _ingestTransaction(
        uint8 action,
        bytes32 queryId,
        uint64 chainKey,
        uint64 blockHeight,
        bytes memory encodedTransaction
    ) internal whenNotPaused {
        if (action > uint8(Action.Generic)) revert UnknownAction(action);

        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        if (!EvmV1Decoder.isValidTransactionType(txType)) revert UnsupportedTransactionType(txType);

        // Decode once and reuse — each call into EvmV1Decoder is a delegatecall that re-encodes
        // the whole payload, and mainnet transactions carry many logs.
        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        if (receipt.receiptStatus != 1) revert SourceTransactionFailed(receipt.receiptStatus);

        IngestContext memory ctx = IngestContext({
            queryId: queryId,
            chainKey: chainKey,
            blockHeight: blockHeight,
            sawSelfFundedBorrow: _hasSelfFundedBorrow(receipt, chainKey),
            repaymentCounted: false
        });

        uint256 ingested;
        for (uint256 i = 0; i < receipt.receiptLogs.length; ++i) {
            EvmV1Decoder.LogEntry memory log = receipt.receiptLogs[i];
            // Anonymous logs have no topic0 to route on. Not hypothetical: log index 4 of the
            // mainnet transaction behind our own headline demo is one, so without this the
            // flagship proof reverts on `topics[0]`.
            if (log.topics.length == 0) continue;

            // Source authentication. Topic filtering alone proves nothing about provenance, and a
            // mainnet transaction's logs come from many unrelated contracts.
            SourceKind kind = sources[chainKey][log.address_];
            if (kind == SourceKind.None) continue;

            if (_route(kind, log, ctx)) ++ingested;
        }

        if (ingested == 0) revert NoRecognisedEvents();
    }

    /// @notice Detects a repayment that was funded by a borrow in the very same transaction.
    ///
    /// @dev This is the flash-loan guard, and it closes the hole that made every other capacity
    /// control decorative.
    ///
    /// Aave V3 imposes no same-block borrow/repay restriction. So one transaction can flash-loan
    /// an arbitrary sum at zero fee, supply it, borrow against it, repay immediately, withdraw,
    /// and return the flash loan — emitting a completely genuine `Repay` for an arbitrary amount
    /// with **no capital at risk for any length of time**. Every proof of it verifies, because
    /// nothing about it is fake. `docs/THREAT_MODEL.md` previously argued that capacity being the
    /// largest *single* repayment bounded this; it does not, because that bound only exists if
    /// loan size is bounded by the attacker's own capital, and largest-single is precisely what a
    /// flash loan maximises.
    ///
    /// A flash loan cannot span blocks, so same-transaction pairing is the discriminator. We match
    /// on `(emitter, reserve, onBehalfOf)` — a borrow of the same asset, from the same pool, for
    /// the same account — which leaves an ordinary borrower who genuinely repays one debt and
    /// opens an unrelated one in a single transaction unaffected.
    ///
    /// This does not close *multi-block* wash lending, where the attacker really does hold the
    /// debt and pay interest. Bounding that needs duration-weighted capacity, which we have not
    /// built and say so.
    function _hasSelfFundedBorrow(EvmV1Decoder.ReceiptFields memory receipt, uint64 chainKey)
        private
        view
        returns (bool)
    {
        uint256 count = receipt.receiptLogs.length;

        for (uint256 i = 0; i < count; ++i) {
            EvmV1Decoder.LogEntry memory borrowLog = receipt.receiptLogs[i];
            if (borrowLog.topics.length < 3 || borrowLog.topics[0] != EventSigs.AAVE_BORROW) continue;
            // Only a registered pool's borrow counts; anyone can emit this shape.
            if (sources[chainKey][borrowLog.address_] != SourceKind.AaveV3) continue;

            for (uint256 j = 0; j < count; ++j) {
                EvmV1Decoder.LogEntry memory repayLog = receipt.receiptLogs[j];
                if (repayLog.topics.length < 3 || repayLog.topics[0] != EventSigs.AAVE_REPAY) continue;
                if (repayLog.address_ != borrowLog.address_) continue;

                // topics[1] = reserve, topics[2] = the account the debt belongs to.
                if (repayLog.topics[1] == borrowLog.topics[1] && repayLog.topics[2] == borrowLog.topics[2]) {
                    return true;
                }
            }
        }

        return false;
    }

    /// @dev Dispatches one recognised log to its protocol decoder.
    /// @return handled True when the log matched an event this source kind understands.
    function _route(SourceKind kind, EvmV1Decoder.LogEntry memory log, IngestContext memory ctx)
        private
        returns (bool handled)
    {
        bytes32 sig = log.topics[0];

        if (kind == SourceKind.LoanBook) {
            if (sig == EventSigs.LOAN_OPENED) return _ingestLoanOpened(log, ctx);
            if (sig == EventSigs.REPAYMENT_MADE) return _ingestLoanBookRepayment(log, ctx);
            if (sig == EventSigs.COLLATERAL_ADDED) return _ingestCollateral(log, ctx);
            return false;
        }

        if (kind == SourceKind.AaveV3) {
            if (sig == EventSigs.AAVE_REPAY) return _ingestAaveRepay(log, ctx);
            if (sig == EventSigs.AAVE_LIQUIDATION) return _ingestAaveLiquidation(log, ctx);
            // `Borrow` is recognised but scores nothing on its own — borrowing is not
            // creditworthiness, repaying is. It is accepted so a borrow-and-repay pair in one
            // transaction does not fail the "no recognised events" check.
            if (sig == EventSigs.AAVE_BORROW) return true;
            return false;
        }

        if (kind == SourceKind.EnsRegistrar) {
            if (sig == EventSigs.ENS_REGISTERED_V4 || sig == EventSigs.ENS_REGISTERED_V3) {
                return _ingestEnsRegistration(log, ctx, sig);
            }
            return false;
        }

        if (kind == SourceKind.ProofOfHumanity) {
            if (sig == EventSigs.POH_UPDATE_INITIATED) return _ingestHumanity(log, ctx);
            return false;
        }

        return false;
    }

    // ─── Sepolia LoanBook decoders ────────────────────────────────────────────────────────

    /// @dev `LoanOpened(uint256 indexed loanId, address indexed borrower, uint256 principal, uint64 dueDate)`
    function _ingestLoanOpened(EvmV1Decoder.LogEntry memory log, IngestContext memory ctx)
        private
        returns (bool)
    {
        if (log.topics.length != 3 || log.data.length != 64) return false;

        uint256 loanId = uint256(log.topics[1]);
        address borrower = _addressFromTopic(log.topics[2]);
        (uint256 principal,) = abi.decode(log.data, (uint256, uint64));

        bytes32 key = _loanKey(ctx.chainKey, log.address_, loanId);
        LoanRecord storage loan = loans[key];
        if (loan.principal == 0) {
            loan.borrower = borrower;
            loan.principal = principal;
            profiles[borrower].loansOpened += 1;
        }

        _touch(borrower, _sourceTime(ctx, 0));
        emit HistoryEventIngested(borrower, ctx.queryId, EventSigs.LOAN_OPENED, ctx.chainKey, loanId);

        // Repayments may have been proven before this opening — each proof is independent, so
        // events can arrive in any order. Re-check closure now the principal is known.
        _reconcile(key);
        _refreshScore(borrower);
        return true;
    }

    /// @dev `RepaymentMade(uint256 indexed loanId, address indexed borrower, address indexed payer,
    /// uint256 amount, bool onTime, uint64 timestamp)`
    ///
    /// The `payer` topic is why LoanBook was redeployed. Repayment is permissionless — a friend
    /// settling your debt should build *your* reputation — but lateness is punitive, so without
    /// knowing who paid, a stranger could settle 1 wei on your past-due loan and brand you with an
    /// indelible `late`: −150 points and Platinum barred forever, for the price of gas. Credit for
    /// the repayment still accrues to the borrower whoever pays; only the *penalty* is restricted
    /// to the borrower's own conduct.
    function _ingestLoanBookRepayment(EvmV1Decoder.LogEntry memory log, IngestContext memory ctx)
        private
        returns (bool)
    {
        if (log.topics.length != 4 || log.data.length != 96) return false;

        uint256 loanId = uint256(log.topics[1]);
        address borrower = _addressFromTopic(log.topics[2]);
        address payer = _addressFromTopic(log.topics[3]);
        (uint256 amount, bool onTime, uint64 timestamp) = abi.decode(log.data, (uint256, bool, uint64));

        CreditProfile storage profile = profiles[borrower];
        profile.totalRepaidWei += amount;
        // `onTime` is decided by the source chain's own clock and carried in the proven log;
        // Creditcoin cannot re-derive it. This is exactly the field that does not exist on real
        // mainnet lending protocols, which is why they are scored on liquidations instead.
        if (onTime) profile.onTime += 1;
        else if (payer == borrower) profile.late += 1;

        bytes32 key = _loanKey(ctx.chainKey, log.address_, loanId);
        LoanRecord storage loan = loans[key];
        if (loan.borrower == address(0)) loan.borrower = borrower;
        loan.repaid += amount;

        _touch(borrower, timestamp);
        emit HistoryEventIngested(borrower, ctx.queryId, EventSigs.REPAYMENT_MADE, ctx.chainKey, loanId);

        _reconcile(key);
        _refreshScore(borrower);
        return true;
    }

    /// @dev `CollateralAdded(address indexed borrower, uint256 amount)`
    function _ingestCollateral(EvmV1Decoder.LogEntry memory log, IngestContext memory ctx)
        private
        returns (bool)
    {
        if (log.topics.length != 2 || log.data.length != 32) return false;

        address borrower = _addressFromTopic(log.topics[1]);
        profiles[borrower].totalCollateralWei += abi.decode(log.data, (uint256));

        _touch(borrower, _sourceTime(ctx, 0));
        emit HistoryEventIngested(borrower, ctx.queryId, EventSigs.COLLATERAL_ADDED, ctx.chainKey, 0);
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
    function _ingestAaveRepay(EvmV1Decoder.LogEntry memory log, IngestContext memory ctx)
        private
        returns (bool)
    {
        if (log.topics.length != 4 || log.data.length != 64) return false;

        address reserve = _addressFromTopic(log.topics[1]);
        address borrower = _addressFromTopic(log.topics[2]);
        (uint256 amount,) = abi.decode(log.data, (uint256, bool));

        // Reject rather than ingest-for-zero. Returning true here would consume the transaction's
        // queryId forever, so the same proof could never be resubmitted after the owner registered
        // the asset — destroying the borrower's largest repayment instead of deferring it, and
        // handing anyone a front-run that caps a victim's capacity at zero permanently.
        if (reserveDecimals[reserve] == 0) revert UnregisteredReserve(reserve);

        CreditProfile storage profile = profiles[borrower];

        // One repayment credit per proven transaction, however many Repay logs it carries.
        // Otherwise a single transaction emitting five repayments awards the full 600-point
        // mainnet term from one proof — which is exactly what a flash-loan attacker would build.
        if (!ctx.repaymentCounted) {
            profile.mainnetRepayments += 1;
            ctx.repaymentCounted = true;
        }

        uint256 normalised = _normalise(reserve, amount);
        profile.totalRepaidWei += normalised;

        // Capacity is the largest single repayment, not the sum: repaying 1 ETH a hundred times
        // demonstrates the ability to handle 1 ETH, not 100.
        //
        // But only when the money was genuinely the borrower's to repay. A repayment funded by a
        // borrow in the same transaction is a flash loan wearing a repayment's clothes: real
        // event, real proof, zero capital at risk. It still counts as a repayment; it just proves
        // no capacity, which is the thing that actually unlocks undercollateralized credit.
        if (!ctx.sawSelfFundedBorrow && normalised > profile.demonstratedCapacityWei) {
            profile.demonstratedCapacityWei = normalised;
            emit CapacityDemonstrated(borrower, normalised);
        }

        _touch(borrower, _sourceTime(ctx, 0));
        emit HistoryEventIngested(borrower, ctx.queryId, EventSigs.AAVE_REPAY, ctx.chainKey, 0);
        _refreshScore(borrower);
        return true;
    }

    /// @dev `LiquidationCall(address indexed collateralAsset, address indexed debtAsset, address indexed user, ...)`
    ///
    /// The mainnet analogue of a default. Rare enough to be high-signal — roughly one per 9,500
    /// blocks across all of Aave V3 — so a long borrowing record with none is meaningful, and a
    /// single one bars Platinum outright.
    function _ingestAaveLiquidation(EvmV1Decoder.LogEntry memory log, IngestContext memory ctx)
        private
        returns (bool)
    {
        if (log.topics.length != 4) return false;

        address borrower = _addressFromTopic(log.topics[3]);
        profiles[borrower].liquidations += 1;

        _touch(borrower, _sourceTime(ctx, 0));
        emit Liquidated(borrower, ctx.chainKey);
        emit HistoryEventIngested(borrower, ctx.queryId, EventSigs.AAVE_LIQUIDATION, ctx.chainKey, 0);
        _refreshScore(borrower);
        return true;
    }

    /// @dev `NameRegistered(... bytes32 indexed labelhash, address indexed owner, ... uint256 expires ...)`
    ///
    /// Not credit — a sunk cost with a provable expiry, worth roughly $25 for five years. A rate
    /// limiter on cheap identity creation, never a licence to borrow. The expiry is enforced
    /// against Creditcoin's clock so a lapsed name cannot be replayed as a current one.
    function _ingestEnsRegistration(EvmV1Decoder.LogEntry memory log, IngestContext memory ctx, bytes32 sig)
        private
        returns (bool)
    {
        if (log.topics.length != 3) return false;

        address owner = _addressFromTopic(log.topics[2]);
        uint256 expires = _ensExpiry(log.data, sig);
        if (expires == 0 || expires <= block.timestamp) return false;

        CreditProfile storage profile = profiles[owner];
        if (uint64(expires) > profile.identityExpiry) profile.identityExpiry = uint64(expires);

        _touch(owner, _sourceTime(ctx, 0));
        emit HistoryEventIngested(owner, ctx.queryId, sig, ctx.chainKey, 0);
        _refreshScore(owner);
        return true;
    }

    /// @dev `UpdateInitiated(bytes20 indexed humanityId, address indexed owner, uint40 expirationTime, bool claimed, address gateway)`
    ///
    /// Implemented, and it verifies — but see `docs/THREAT_MODEL.md`: mainnet Proof of Humanity
    /// holds 55 humanities, because the real population lives on Gnosis, which Creditcoin does not
    /// attest. It is here because it is the only mainnet personhood event carrying both an address
    /// and a self-describing expiry, not because it is load-bearing.
    function _ingestHumanity(EvmV1Decoder.LogEntry memory log, IngestContext memory ctx)
        private
        returns (bool)
    {
        if (log.topics.length != 3 || log.data.length < 96) return false;

        address owner = _addressFromTopic(log.topics[2]);
        (uint256 expirationTime, bool claimed,) = abi.decode(log.data, (uint256, bool, address));
        if (!claimed || expirationTime <= block.timestamp) return false;

        CreditProfile storage profile = profiles[owner];
        if (uint64(expirationTime) > profile.identityExpiry) profile.identityExpiry = uint64(expirationTime);

        _touch(owner, _sourceTime(ctx, 0));
        emit HistoryEventIngested(owner, ctx.queryId, EventSigs.POH_UPDATE_INITIATED, ctx.chainKey, 0);
        _refreshScore(owner);
        return true;
    }

    // ─── Internals ────────────────────────────────────────────────────────────────────────

    /// @dev Extracts `expires` from an ENS `NameRegistered` log's non-indexed data.
    ///
    /// Both controller versions we accept carry **four** non-indexed words, differing only in the
    /// tail:
    ///   v4 `(string label, uint256 baseCost, uint256 premium, uint256 expires, bytes32 referrer)`
    ///   v3 `(string name,  uint256 baseCost, uint256 premium, uint256 expires)`
    ///
    /// The v3 branch used to decode a *three*-word layout and return the second `uint256`, which
    /// is `premium`, not `expires`. That was wrong in both directions: `premium` is normally 0, so
    /// genuine registrations were silently dropped by the expiry gate — but a name bought inside
    /// the post-expiry premium-decay window carries a premium around 1e26, which sails past the
    /// gate and grants a permanent identity bonus. The layout it was written against belongs to
    /// the five-argument v1/v2 event, whose topic0 this contract has never accepted.
    ///
    /// Returns 0 when the payload is too short to hold the layout, so a malformed log is ignored
    /// rather than reverting the whole transaction — the previous NatSpec promised this but no
    /// guard implemented it, and `abi.decode` reverts on a short buffer.
    function _ensExpiry(bytes memory data, bytes32 sig) private pure returns (uint256) {
        // offset + baseCost + premium + expires, plus the string's own length word.
        if (data.length < 160) return 0;

        if (sig == EventSigs.ENS_REGISTERED_V4) {
            if (data.length < 192) return 0;
            (,,, uint256 expires,) = abi.decode(data, (string, uint256, uint256, uint256, bytes32));
            return expires;
        }

        (,,, uint256 expiresV3) = abi.decode(data, (string, uint256, uint256, uint256));
        return expiresV3;
    }

    /// @dev Identifies a loan by its full source identity, not by its id alone. Loan ids are small
    /// per-contract integers, so two LoanBook deployments both mint a loan `1`.
    function _loanKey(uint64 chainKey, address emitter, uint256 loanId) private pure returns (bytes32) {
        return keccak256(abi.encode(chainKey, emitter, loanId));
    }

    /// @dev Converts a proven source-chain block height into an approximate wall-clock time.
    /// Returns `fallbackTimestamp` when the chain has no registered anchor, and 0 when there is no
    /// fallback either — `_touch` treats 0 as "no information" rather than as the epoch.
    function _sourceTime(IngestContext memory ctx, uint64 fallbackTimestamp) private view returns (uint64) {
        ChainAnchor memory anchor = chainAnchors[ctx.chainKey];
        if (anchor.timestamp == 0 || ctx.blockHeight == 0) return fallbackTimestamp;

        if (ctx.blockHeight >= anchor.height) {
            return anchor.timestamp + uint64(ctx.blockHeight - anchor.height) * anchor.secondsPerBlock;
        }

        uint64 delta = uint64(anchor.height - ctx.blockHeight) * anchor.secondsPerBlock;
        // A height far enough below the anchor to predate the epoch means the anchor is wrong;
        // report "no information" rather than a nonsensical date.
        return delta >= anchor.timestamp ? fallbackTimestamp : anchor.timestamp - delta;
    }

    /// @dev Marks a loan closed once proven repayments cover its principal. Idempotent, and safe
    /// whichever order the proofs arrive in.
    function _reconcile(bytes32 key) private {
        LoanRecord storage loan = loans[key];
        if (loan.closed || loan.principal == 0 || loan.repaid < loan.principal) return;

        loan.closed = true;
        profiles[loan.borrower].loansClosed += 1;
        emit LoanClosed(loan.borrower, uint256(key));
    }

    /// @dev Records first contact and, where the source gives one, the earliest source-chain
    /// timestamp seen. That timestamp is the score's time axis — the one input a scripted
    /// attacker cannot compress.
    function _touch(address borrower, uint64 sourceTimestamp) private {
        CreditProfile storage profile = profiles[borrower];
        if (profile.firstSeen == 0) profile.firstSeen = uint64(block.timestamp);

        // Fall back to now when neither the event nor the chain anchor can date this proof; a
        // later, older proof will correct it downward, which only ever helps the borrower and
        // cannot be gamed upward.
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

    /// @dev Scales a reserve-denominated amount to 18 decimals. Callers must reject an
    /// unregistered reserve before reaching here — the zero return is a backstop, not a policy.
    ///
    /// Note this normalises **units, not value** — one USDC and one DAI are treated alike, and no
    /// price conversion happens, because a price feed for a foreign chain's assets is exactly the
    /// oracle dependency this project exists to avoid. Stablecoins dominate Aave borrowing, so
    /// face value is a reasonable approximation; the limitation is stated in docs/THREAT_MODEL.md.
    function _normalise(address reserve, uint256 amount) private view returns (uint256) {
        uint8 decimals = reserveDecimals[reserve];
        if (decimals == 0) return 0;
        if (decimals >= 18) return amount;
        return amount * (10 ** (18 - decimals));
    }

    /// @dev An indexed `address` occupies the low 20 bytes of its topic.
    function _addressFromTopic(bytes32 topic) private pure returns (address) {
        return address(uint160(uint256(topic)));
    }
}
