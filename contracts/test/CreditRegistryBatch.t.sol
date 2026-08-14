// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";
import {CreditRegistry} from "../src/creditcoin/CreditRegistry.sol";
import {CreditProfile, ScoreLib, Tier} from "../src/creditcoin/ScoreLib.sol";
import {INativeQueryVerifier, NativeQueryVerifierLib} from "../src/vendored/VerifierInterface.sol";
import {MockNativeQueryVerifier} from "./mocks/MockNativeQueryVerifier.sol";
import {EncodedTxBuilder} from "./helpers/EncodedTxBuilder.sol";
import {SourceKind, EventSigs} from "../src/creditcoin/SourceKinds.sol";

/// @notice Tests for batch verification — importing a whole credit history in one transaction.
///
/// @dev The batch path is the one surface with no precedent in Gluwa's example repository, so it
/// gets the most adversarial treatment. Two properties matter above the rest:
///
///   **Atomicity.** One bad proof reverts the entire batch. A partially-applied credit history is
///   worse than none, because the borrower would have no way to tell which half landed.
///
///   **In-batch duplicate detection.** Two copies of one proof inside a single batch must not both
///   count. This is why {CreditRegistry-executeBatch} reserves query ids *before* verifying rather
///   than after: a "not yet processed" check performed up front for every item would pass twice.
contract CreditRegistryBatchTest is Test {
    CreditRegistry internal registry;
    MockNativeQueryVerifier internal verifier;

    address internal constant LOANBOOK = address(0x10A4B00c0fFEe0000000000000000000000B0057);
    address internal constant IMPOSTOR = address(0xbAdc0dE000000000000000000000000000000BAd);
    uint64 internal constant SEPOLIA_KEY = 1;

    address internal borrower = makeAddr("borrower");
    uint256 internal constant PRINCIPAL = 0.002 ether;
    uint64 internal constant BASE_HEIGHT = 11_483_178;

    function setUp() public {
        MockNativeQueryVerifier deployed = new MockNativeQueryVerifier();
        vm.etch(NativeQueryVerifierLib.PRECOMPILE_ADDRESS, address(deployed).code);
        verifier = MockNativeQueryVerifier(NativeQueryVerifierLib.PRECOMPILE_ADDRESS);
        verifier.setShouldVerify(true);

        registry = new CreditRegistry();
        registry.registerSource(SEPOLIA_KEY, LOANBOOK, SourceKind.LoanBook);
        vm.warp(1_786_000_000);
    }

    // ─── Batch construction helpers ───────────────────────────────────────────────────────

    struct Batch {
        uint8[] actions;
        uint64[] heights;
        bytes[] payloads;
        INativeQueryVerifier.MerkleProof[] proofs;
    }

    function _alloc(uint256 n) internal pure returns (Batch memory b) {
        b.actions = new uint8[](n);
        b.heights = new uint64[](n);
        b.payloads = new bytes[](n);
        b.proofs = new INativeQueryVerifier.MerkleProof[](n);
    }

    /// @dev Each item gets a distinct merkle root so the mock derives a distinct txIndex, and
    /// therefore a distinct query id — mirroring how real proofs differ.
    function _proofFor(uint256 seed) internal pure returns (INativeQueryVerifier.MerkleProof memory p) {
        INativeQueryVerifier.MerkleProofEntry[] memory siblings =
            new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: bytes32(seed), isLeft: true});
        p = INativeQueryVerifier.MerkleProof({root: bytes32(seed), siblings: siblings});
    }

    /// @dev A batch of `n` on-time repayments, each on its own loan and block.
    function _repaymentBatch(uint256 n) internal view returns (Batch memory b) {
        b = _alloc(n);
        for (uint256 i = 0; i < n; ++i) {
            b.actions[i] = uint8(CreditRegistry.Action.Generic);
            b.heights[i] = BASE_HEIGHT + uint64(i);
            b.payloads[i] = EncodedTxBuilder.single(
                EncodedTxBuilder.repaymentMade(
                    LOANBOOK, EventSigs.REPAYMENT_MADE, i + 1, borrower, PRINCIPAL, true
                )
            );
            b.proofs[i] = _proofFor(i + 1);
        }
    }

    function _shared() internal pure returns (INativeQueryVerifier.ContinuityProof memory) {
        bytes32[] memory roots = new bytes32[](3);
        roots[0] = bytes32(uint256(0xc0));
        roots[1] = bytes32(uint256(0xc1));
        roots[2] = bytes32(uint256(0xc2));
        return INativeQueryVerifier.ContinuityProof({
            lowerEndpointDigest: bytes32(uint256(0xab)),
            roots: roots
        });
    }

    function _submit(Batch memory b) internal returns (bool) {
        return registry.executeBatch(b.actions, SEPOLIA_KEY, b.heights, b.payloads, b.proofs, _shared());
    }

    // ─── Happy paths ──────────────────────────────────────────────────────────────────────

    function test_batch_singleItemSucceeds() public {
        assertTrue(_submit(_repaymentBatch(1)));
        assertEq(registry.profileOf(borrower).onTime, 1);
    }

    /// @dev The headline: a full history verified in one Creditcoin transaction.
    function test_batch_maxSizeTenSucceeds() public {
        assertTrue(_submit(_repaymentBatch(10)));

        CreditProfile memory p = registry.profileOf(borrower);
        assertEq(p.onTime, 10, "all ten repayments applied");
        assertEq(p.totalRepaidWei, PRINCIPAL * 10);
    }

    /// @dev One shared continuity proof covers every item — the reason a batch is cheaper than N
    /// single verifications.
    function test_batch_usesOneVerifierCallForAllItems() public {
        vm.recordLogs();
        _submit(_repaymentBatch(5));

        uint256 verifications;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; ++i) {
            if (entries[i].topics[0] == keccak256("TransactionVerifiedMock(uint64,uint64,uint64)")) {
                ++verifications;
            }
        }
        // The precompile emits one event per proof, but from a single call.
        assertEq(verifications, 5);
    }

    function test_batch_mixedEventTypesAllApplied() public {
        Batch memory b = _alloc(3);

        b.actions[0] = uint8(CreditRegistry.Action.Generic);
        b.heights[0] = BASE_HEIGHT;
        b.payloads[0] = EncodedTxBuilder.single(
            EncodedTxBuilder.loanOpened(
                LOANBOOK, EventSigs.LOAN_OPENED, 1, borrower, PRINCIPAL, uint64(block.timestamp + 1 days)
            )
        );
        b.proofs[0] = _proofFor(1);

        b.actions[1] = uint8(CreditRegistry.Action.Generic);
        b.heights[1] = BASE_HEIGHT + 1;
        b.payloads[1] = EncodedTxBuilder.single(
            EncodedTxBuilder.collateralAdded(LOANBOOK, EventSigs.COLLATERAL_ADDED, borrower, 0.003 ether)
        );
        b.proofs[1] = _proofFor(2);

        b.actions[2] = uint8(CreditRegistry.Action.Generic);
        b.heights[2] = BASE_HEIGHT + 2;
        b.payloads[2] = EncodedTxBuilder.single(
            EncodedTxBuilder.repaymentMade(LOANBOOK, EventSigs.REPAYMENT_MADE, 1, borrower, PRINCIPAL, true)
        );
        b.proofs[2] = _proofFor(3);

        _submit(b);

        CreditProfile memory p = registry.profileOf(borrower);
        assertEq(p.loansOpened, 1);
        assertEq(p.totalCollateralWei, 0.003 ether);
        assertEq(p.onTime, 1);
        assertEq(p.loansClosed, 1, "loan closed within the same batch");
    }

    /// @dev Borrower C's real seeded shape: 3 loans, 5 on-time repayments, 1 collateral deposit —
    /// nine proofs verified in a single transaction.
    ///
    /// It lands at **Silver, not Platinum**, and that is the point. This history came from our own
    /// `LoanBook`, which has no lender, so it is cheap to manufacture; `ScoreLib` caps such signals
    /// below the tier that lends more than the borrower posts. An earlier version of this test
    /// asserted Platinum, which is precisely the hole that reading real mainnet history closed.
    function test_batch_wholeHistoryImportsInOneTransaction() public {
        Batch memory b = _alloc(9);
        uint256 slot;

        for (uint256 loan = 1; loan <= 3; ++loan) {
            b.actions[slot] = uint8(CreditRegistry.Action.Generic);
            b.heights[slot] = BASE_HEIGHT + uint64(slot);
            b.payloads[slot] = EncodedTxBuilder.single(
                EncodedTxBuilder.loanOpened(
                    LOANBOOK, EventSigs.LOAN_OPENED, loan, borrower, PRINCIPAL, uint64(block.timestamp + 30 days)
                )
            );
            b.proofs[slot] = _proofFor(slot + 1);
            ++slot;

            uint256 repayments = loan == 2 ? 1 : 2;
            for (uint256 r = 0; r < repayments; ++r) {
                uint256 amount = repayments == 1 ? PRINCIPAL : PRINCIPAL / 2;
                b.actions[slot] = uint8(CreditRegistry.Action.Generic);
                b.heights[slot] = BASE_HEIGHT + uint64(slot);
                b.payloads[slot] = EncodedTxBuilder.single(
                    EncodedTxBuilder.repaymentMade(
                        LOANBOOK, EventSigs.REPAYMENT_MADE, loan, borrower, amount, true
                    )
                );
                b.proofs[slot] = _proofFor(slot + 1);
                ++slot;
            }

            if (loan == 2) {
                b.actions[slot] = uint8(CreditRegistry.Action.Generic);
                b.heights[slot] = BASE_HEIGHT + uint64(slot);
                b.payloads[slot] = EncodedTxBuilder.single(
                    EncodedTxBuilder.collateralAdded(
                        LOANBOOK, EventSigs.COLLATERAL_ADDED, borrower, 0.003 ether
                    )
                );
                b.proofs[slot] = _proofFor(slot + 1);
                ++slot;
            }
        }

        assertEq(slot, 9, "nine proofs, within MAX_BATCH_SIZE");
        assertEq(uint8(registry.tierOf(borrower)), uint8(Tier.Bronze), "starts Bronze");

        _submit(b);

        CreditProfile memory p = registry.profileOf(borrower);
        assertEq(p.onTime, 5, "all five repayments applied");
        assertEq(p.loansClosed, 3, "closure derived from proven repayments");
        assertEq(registry.scoreOf(borrower), 390, "matches ScoreLib's documented arithmetic");
        assertEq(
            uint8(registry.tierOf(borrower)),
            uint8(Tier.Silver),
            "self-dealt history reaches Silver, never Platinum"
        );
    }

    // ─── Size and shape ───────────────────────────────────────────────────────────────────

    function test_batch_rejectsEmpty() public {
        Batch memory b = _alloc(0);
        vm.expectRevert(CreditRegistry.EmptyBatch.selector);
        _submit(b);
    }

    /// @dev Eleven proofs revert on the live precompile with `heights: Value is too large for
    /// length`. We reject earlier, with a clearer error, before spending gas on the call.
    function test_batch_rejectsOversized() public {
        Batch memory b = _repaymentBatch(11);
        vm.expectRevert(abi.encodeWithSelector(CreditRegistry.BatchTooLarge.selector, uint256(11), uint256(10)));
        _submit(b);
    }

    function test_batch_rejectsLengthMismatch() public {
        Batch memory b = _repaymentBatch(3);
        uint8[] memory shortActions = new uint8[](2);
        vm.expectRevert(CreditRegistry.BatchLengthMismatch.selector);
        registry.executeBatch(shortActions, SEPOLIA_KEY, b.heights, b.payloads, b.proofs, _shared());
    }

    // ─── Atomicity and replay ─────────────────────────────────────────────────────────────

    /// @dev The case early query-id reservation exists to catch. Both copies would pass a naive
    /// up-front "not yet processed" check and be counted twice.
    function test_batch_rejectsDuplicateWithinSameBatch() public {
        Batch memory b = _repaymentBatch(2);
        // Make the second item identical to the first: same height, same proof, same query id.
        b.heights[1] = b.heights[0];
        b.proofs[1] = b.proofs[0];

        vm.expectRevert();
        _submit(b);

        assertEq(registry.profileOf(borrower).onTime, 0, "nothing applied");
    }

    function test_batch_rejectsItemAlreadyIngestedIndividually() public {
        Batch memory first = _repaymentBatch(1);
        _submit(first);
        assertEq(registry.profileOf(borrower).onTime, 1);

        // A larger batch that re-includes the already-verified transaction.
        Batch memory second = _repaymentBatch(3);
        vm.expectRevert();
        _submit(second);

        assertEq(registry.profileOf(borrower).onTime, 1, "batch reverted whole; no partial apply");
    }

    /// @dev Atomicity: an unrecognised emitter anywhere in the batch discards everything, so a
    /// borrower never ends up with a half-imported history.
    function test_batch_oneBadItemRevertsEntireBatch() public {
        Batch memory b = _repaymentBatch(3);
        b.payloads[2] = EncodedTxBuilder.single(
            EncodedTxBuilder.repaymentMade(IMPOSTOR, EventSigs.REPAYMENT_MADE, 3, borrower, PRINCIPAL, true)
        );

        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        _submit(b);

        assertEq(registry.profileOf(borrower).onTime, 0, "the two valid items were discarded too");
    }

    function test_batch_rejectsWrongSourceChain() public {
        Batch memory b = _repaymentBatch(2);
        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        registry.executeBatch(b.actions, 3, b.heights, b.payloads, b.proofs, _shared());
    }

    function test_batch_rejectsForgedProof() public {
        Batch memory b = _repaymentBatch(3);
        verifier.setShouldVerify(false);

        vm.expectRevert(MockNativeQueryVerifier.MockProofRejected.selector);
        _submit(b);

        assertEq(registry.profileOf(borrower).onTime, 0);
    }

    /// @dev A rejected batch must leave every query id unconsumed, or a forged submission could
    /// permanently censor ten legitimate transactions at once.
    function test_batch_rejectedBatchDoesNotBurnQueryIds() public {
        Batch memory b = _repaymentBatch(3);

        verifier.setShouldVerify(false);
        vm.expectRevert(MockNativeQueryVerifier.MockProofRejected.selector);
        _submit(b);

        verifier.setShouldVerify(true);
        assertTrue(_submit(b), "the same batch succeeds once proofs verify");
        assertEq(registry.profileOf(borrower).onTime, 3);
    }

    function test_batch_rejectsWhenPaused() public {
        Batch memory b = _repaymentBatch(2);
        registry.pause();

        vm.expectRevert();
        _submit(b);
    }
}
