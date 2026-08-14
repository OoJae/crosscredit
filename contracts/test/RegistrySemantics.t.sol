// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";
import {CreditRegistry} from "../src/creditcoin/CreditRegistry.sol";
import {CreditProfile, ScoreLib, Tier} from "../src/creditcoin/ScoreLib.sol";
import {INativeQueryVerifier, NativeQueryVerifierLib} from "../src/vendored/VerifierInterface.sol";
import {MockNativeQueryVerifier} from "./mocks/MockNativeQueryVerifier.sol";
import {EncodedTxBuilder} from "./helpers/EncodedTxBuilder.sol";
import {SourceKind, EventSigs} from "../src/creditcoin/SourceKinds.sol";

/// @notice Semantics the audit found were asserted in prose but nowhere in code: who a penalty
/// belongs to, what the age term actually measures, which ENS layout we decode, and whether a loan
/// id means anything on its own.
contract RegistrySemanticsTest is Test {
    CreditRegistry internal registry;
    MockNativeQueryVerifier internal verifier;

    address internal constant LOANBOOK = address(0x10A4B00c0fFEe0000000000000000000000B0057);
    address internal constant OTHER_LOANBOOK = address(0x10A4B00c0ffee0000000000000000000000B0058);
    address internal constant ENS_V4 = 0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547;
    address internal constant ENS_V3 = 0x253553366Da8546fC250F225fe3d25d0C782303b;
    address internal constant POH_V2 = 0xa478095886659168E8812154fB0DE39F103E74b2;

    uint64 internal constant SEPOLIA = 1;
    uint64 internal constant MAINNET = 3;
    uint64 internal constant NOW = 1_786_000_000;

    /// @dev Mainnet heights and their real times, used as the anchor under test.
    uint64 internal constant ANCHOR_HEIGHT = 21_000_000;
    uint64 internal constant ANCHOR_TIME = 1_735_689_600; // 2025-01-01
    uint32 internal constant SECONDS_PER_BLOCK = 12;

    address internal borrower = address(0x1111111111111111111111111111111111111111);
    address internal stranger = address(0x2222222222222222222222222222222222222222);
    address internal relayer = makeAddr("relayer");

    uint256 private _salt;

    function setUp() public {
        MockNativeQueryVerifier deployed = new MockNativeQueryVerifier();
        vm.etch(NativeQueryVerifierLib.PRECOMPILE_ADDRESS, address(deployed).code);
        verifier = MockNativeQueryVerifier(NativeQueryVerifierLib.PRECOMPILE_ADDRESS);
        verifier.setShouldVerify(true);

        registry = new CreditRegistry();
        registry.registerSource(SEPOLIA, LOANBOOK, SourceKind.LoanBook);
        registry.registerSource(MAINNET, ENS_V4, SourceKind.EnsRegistrar);
        registry.registerSource(MAINNET, ENS_V3, SourceKind.EnsRegistrar);
        registry.registerSource(MAINNET, POH_V2, SourceKind.ProofOfHumanity);
        registry.registerChainAnchor(MAINNET, ANCHOR_HEIGHT, ANCHOR_TIME, SECONDS_PER_BLOCK);

        vm.warp(NOW);
    }

    function _submit(uint64 chainKey, uint64 height, bytes memory payload) internal {
        bytes32 salt = bytes32(++_salt);
        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: salt, isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));

        vm.prank(relayer);
        registry.execute(0, chainKey, height, payload, salt, siblings, bytes32(uint256(0xab)), roots);
    }

    // ─── Lateness belongs to the borrower, not to whoever paid ────────────────────────────

    /// A stranger settling 1 wei on a past-due loan used to stamp an indelible `late` on the
    /// borrower: −150 points and Platinum barred forever, for the price of gas. Ingestion is
    /// permissionless and the borrower is read from a topic, so nothing stopped it.
    function test_late_isNotChargedWhenAThirdPartyPaid() public {
        _submit(
            SEPOLIA,
            11_482_800,
            EncodedTxBuilder.single(
                EncodedTxBuilder.repaymentMadeBy(
                    LOANBOOK, EventSigs.REPAYMENT_MADE, 1, borrower, stranger, 1, false, NOW
                )
            )
        );

        CreditProfile memory p = registry.profileOf(borrower);
        assertEq(p.late, 0, "a stranger's lateness is not the borrower's default");
        assertEq(p.totalRepaidWei, 1, "but the repayment still credits the borrower");
    }

    /// The borrower's own lateness still counts, or the penalty would mean nothing.
    function test_late_isChargedWhenTheBorrowerPaidLate() public {
        _submit(
            SEPOLIA,
            11_482_800,
            EncodedTxBuilder.single(
                EncodedTxBuilder.repaymentMadeBy(
                    LOANBOOK, EventSigs.REPAYMENT_MADE, 1, borrower, borrower, 1 ether, false, NOW
                )
            )
        );

        assertEq(registry.profileOf(borrower).late, 1);
    }

    // ─── The age term measures history, not tenure ────────────────────────────────────────

    /// `oldestActivity` ratchets downward, so proofs may arrive in any order.
    function test_age_oldestActivityWinsRegardlessOfArrivalOrder() public {
        uint64 old = NOW - 400 days;

        _submit(
            SEPOLIA,
            11_482_800,
            EncodedTxBuilder.single(
                EncodedTxBuilder.repaymentMadeBy(LOANBOOK, EventSigs.REPAYMENT_MADE, 1, borrower, borrower, 1, true, NOW)
            )
        );
        _submit(
            SEPOLIA,
            11_482_801,
            EncodedTxBuilder.single(
                EncodedTxBuilder.repaymentMadeBy(LOANBOOK, EventSigs.REPAYMENT_MADE, 2, borrower, borrower, 1, true, old)
            )
        );

        assertEq(registry.profileOf(borrower).oldestActivity, old, "a later proof of older history wins");
    }

    /// The headline fix. Aave, ENS and PoH emit no timestamp, so six of the seven ingest paths used
    /// to stamp `block.timestamp` — making the age term measure time since *import*. That rewarded
    /// importing early and idling, and gave a decade of real history zero age points.
    function test_age_isDerivedFromTheProvenBlockHeight() public {
        // Two years of mainnet blocks below the anchor.
        uint64 height = ANCHOR_HEIGHT - (2 * 365 days) / SECONDS_PER_BLOCK;

        _submit(
            MAINNET,
            height,
            EncodedTxBuilder.single(
                EncodedTxBuilder.ensRegistered(ENS_V4, EventSigs.ENS_REGISTERED_V4, borrower, NOW + 365 days, 0, true)
            )
        );

        uint64 observed = registry.profileOf(borrower).oldestActivity;
        assertApproxEqAbs(observed, ANCHOR_TIME - 2 * 365 days, 1 days, "history is dated from its own chain");
        assertLt(observed, NOW - 700 days, "and is genuinely old, not the ingest time");
    }

    /// Without an anchor there is nothing to date against, so it falls back to now rather than
    /// inventing a date.
    function test_age_fallsBackToNowWithoutAnAnchor() public {
        CreditRegistry fresh = new CreditRegistry();
        fresh.registerSource(MAINNET, ENS_V4, SourceKind.EnsRegistrar);

        bytes32 salt = bytes32(uint256(0xfeed));
        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: salt, isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));

        fresh.execute(
            0,
            MAINNET,
            1_000_000,
            EncodedTxBuilder.single(
                EncodedTxBuilder.ensRegistered(ENS_V4, EventSigs.ENS_REGISTERED_V4, borrower, NOW + 365 days, 0, true)
            ),
            salt,
            siblings,
            bytes32(uint256(0xab)),
            roots
        );

        assertEq(fresh.profileOf(borrower).oldestActivity, NOW);
    }

    function test_anchor_rejectsZeroValues() public {
        vm.expectRevert(CreditRegistry.InvalidAnchor.selector);
        registry.registerChainAnchor(MAINNET, 1, 0, 12);

        vm.expectRevert(CreditRegistry.InvalidAnchor.selector);
        registry.registerChainAnchor(MAINNET, 1, 1, 0);
    }

    function test_anchor_isOwnerOnly() public {
        vm.expectRevert();
        vm.prank(stranger);
        registry.registerChainAnchor(MAINNET, 1, 1, 12);
    }

    // ─── ENS v3 decodes `expires`, not `premium` ──────────────────────────────────────────

    /// The v3 branch decoded a three-word layout and returned the second `uint256` — which is
    /// `premium`, not `expires`. Premium is normally zero, so genuine registrations were silently
    /// dropped by the expiry gate.
    function test_ens_v3RegistrationIsAccepted() public {
        uint256 expires = NOW + 400 days;

        _submit(
            MAINNET,
            ANCHOR_HEIGHT,
            EncodedTxBuilder.single(
                EncodedTxBuilder.ensRegistered(ENS_V3, EventSigs.ENS_REGISTERED_V3, borrower, expires, 0, false)
            )
        );

        assertEq(registry.profileOf(borrower).identityExpiry, uint64(expires), "v3 expiry is read correctly");
    }

    /// The other direction of the same bug: a name bought inside the premium-decay window carries
    /// a premium around 1e26, which sailed past the expiry gate and granted a *permanent* identity
    /// bonus. Reading the correct field means the real expiry governs.
    function test_ens_v3HugePremiumDoesNotForgeAnExpiry() public {
        uint256 lapsed = NOW - 1 days;

        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        _submit(
            MAINNET,
            ANCHOR_HEIGHT,
            EncodedTxBuilder.single(
                EncodedTxBuilder.ensRegistered(ENS_V3, EventSigs.ENS_REGISTERED_V3, borrower, lapsed, 1e26, false)
            )
        );

        assertEq(registry.profileOf(borrower).identityExpiry, 0, "a lapsed name grants nothing");
    }

    function test_ens_v4RegistrationStillWorks() public {
        uint256 expires = NOW + 400 days;

        _submit(
            MAINNET,
            ANCHOR_HEIGHT,
            EncodedTxBuilder.single(
                EncodedTxBuilder.ensRegistered(ENS_V4, EventSigs.ENS_REGISTERED_V4, borrower, expires, 0, true)
            )
        );

        assertEq(registry.profileOf(borrower).identityExpiry, uint64(expires));
    }

    // ─── Proof of Humanity ────────────────────────────────────────────────────────────────

    function test_poh_claimedAndUnexpiredSetsIdentity() public {
        uint256 expires = NOW + 200 days;

        _submit(
            MAINNET,
            ANCHOR_HEIGHT,
            EncodedTxBuilder.single(
                EncodedTxBuilder.pohUpdateInitiated(POH_V2, EventSigs.POH_UPDATE_INITIATED, borrower, expires, true)
            )
        );

        assertEq(registry.profileOf(borrower).identityExpiry, uint64(expires));
    }

    function test_poh_unclaimedIsRejected() public {
        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        _submit(
            MAINNET,
            ANCHOR_HEIGHT,
            EncodedTxBuilder.single(
                EncodedTxBuilder.pohUpdateInitiated(
                    POH_V2, EventSigs.POH_UPDATE_INITIATED, borrower, NOW + 200 days, false
                )
            )
        );
    }

    function test_poh_expiredIsRejected() public {
        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        _submit(
            MAINNET,
            ANCHOR_HEIGHT,
            EncodedTxBuilder.single(
                EncodedTxBuilder.pohUpdateInitiated(POH_V2, EventSigs.POH_UPDATE_INITIATED, borrower, NOW - 1, true)
            )
        );
    }

    // ─── A loan id means nothing without its source ───────────────────────────────────────

    /// Loan ids are small per-contract integers, so two LoanBook deployments both mint a loan `1`.
    /// Keyed on the bare id, one borrower's repayment closed another's loan.
    function test_loans_areKeyedByFullSourceIdentity() public {
        registry.registerSource(SEPOLIA, OTHER_LOANBOOK, SourceKind.LoanBook);

        _submit(
            SEPOLIA,
            11_482_800,
            EncodedTxBuilder.single(
                EncodedTxBuilder.loanOpened(LOANBOOK, EventSigs.LOAN_OPENED, 1, borrower, 10 ether, uint64(NOW + 1 days))
            )
        );
        // Same loan id, different contract, different borrower, tiny principal.
        _submit(
            SEPOLIA,
            11_482_801,
            EncodedTxBuilder.single(
                EncodedTxBuilder.loanOpened(
                    OTHER_LOANBOOK, EventSigs.LOAN_OPENED, 1, stranger, 1, uint64(NOW + 1 days)
                )
            )
        );
        // Repaying the *other* book's loan 1 in full must not touch this book's loan 1.
        _submit(
            SEPOLIA,
            11_482_802,
            EncodedTxBuilder.single(
                EncodedTxBuilder.repaymentMadeBy(
                    OTHER_LOANBOOK, EventSigs.REPAYMENT_MADE, 1, stranger, stranger, 1, true, NOW
                )
            )
        );

        assertEq(registry.profileOf(stranger).loansClosed, 1, "the other book's loan closed");
        assertEq(registry.profileOf(borrower).loansClosed, 0, "this book's 10 ETH loan did not");
    }

    // ─── Scores are live, not cached ──────────────────────────────────────────────────────

    /// The cached score was stale with respect to time, and two of the score's terms are functions
    /// of time. An ENS name could lapse and the borrower would keep paying the identity bonus for
    /// ever, because nothing recomputed between ingests.
    function test_score_dropsWhenAnIdentityLapsesWithoutAnyNewProof() public {
        uint256 expires = NOW + 30 days;
        _submit(
            MAINNET,
            ANCHOR_HEIGHT,
            EncodedTxBuilder.single(
                EncodedTxBuilder.ensRegistered(ENS_V4, EventSigs.ENS_REGISTERED_V4, borrower, expires, 0, true)
            )
        );

        uint16 withIdentity = registry.scoreOf(borrower);
        assertGe(withIdentity, ScoreLib.POINTS_IDENTITY, "the bonus applies while the name is live");

        vm.warp(expires + 1);

        assertEq(
            registry.scoreOf(borrower),
            withIdentity - uint16(ScoreLib.POINTS_IDENTITY),
            "and stops the moment it lapses, with no new proof required"
        );
    }

    // ─── previewIngest ────────────────────────────────────────────────────────────────────

    /// Every guard in the registry reverts, and to a user staring at a failed wallet popup one
    /// revert looks like any other. The preview answers *which*, for free, before signing.
    function test_preview_reportsRecognisedEventsWithoutConsumingTheProof() public {
        bytes memory payload = EncodedTxBuilder.single(
            EncodedTxBuilder.repaymentMadeBy(LOANBOOK, EventSigs.REPAYMENT_MADE, 1, borrower, borrower, 1, true, NOW)
        );

        bytes32 salt = bytes32(uint256(0xbeef));
        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: salt, isLeft: true});

        INativeQueryVerifier.MerkleProof memory merkle =
            INativeQueryVerifier.MerkleProof({root: salt, siblings: siblings});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));
        INativeQueryVerifier.ContinuityProof memory continuity =
            INativeQueryVerifier.ContinuityProof({lowerEndpointDigest: bytes32(uint256(0xab)), roots: roots});

        (uint256 recognised, bool already, bool flashLoan) =
            registry.previewIngest(SEPOLIA, 11_482_800, payload, merkle, continuity);

        assertEq(recognised, 1);
        assertFalse(already, "previewing must not consume the query id");
        assertFalse(flashLoan);

        // And the profile is untouched, because a view cannot write.
        assertEq(registry.profileOf(borrower).firstSeen, 0);
    }

    function test_preview_flagsAnAlreadyProcessedProof() public {
        bytes memory payload = EncodedTxBuilder.single(
            EncodedTxBuilder.repaymentMadeBy(LOANBOOK, EventSigs.REPAYMENT_MADE, 1, borrower, borrower, 1, true, NOW)
        );

        bytes32 salt = bytes32(uint256(1));
        _submit(SEPOLIA, 11_482_800, payload);

        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: salt, isLeft: true});
        INativeQueryVerifier.MerkleProof memory merkle =
            INativeQueryVerifier.MerkleProof({root: salt, siblings: siblings});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));
        INativeQueryVerifier.ContinuityProof memory continuity =
            INativeQueryVerifier.ContinuityProof({lowerEndpointDigest: bytes32(uint256(0xab)), roots: roots});

        (, bool already,) = registry.previewIngest(SEPOLIA, 11_482_800, payload, merkle, continuity);
        assertTrue(already, "the caller learns this would revert before paying for it");
    }
}
