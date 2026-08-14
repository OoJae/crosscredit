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

/// @notice Tests for the Attestcoin Smart Contract that turns verified Sepolia transactions into
/// credit reputation.
/// @dev The mock verifier is installed at the precompile's real address with `vm.etch`, so these
/// exercise the genuine vendored {USCBase} path rather than a stand-in for it. The negative
/// matrix is the substance here: a proof being cryptographically valid says nothing about whether
/// the transaction it proves should be allowed to move someone's credit score.
contract CreditRegistryTest is Test {
    CreditRegistry internal registry;
    MockNativeQueryVerifier internal verifier;

    address internal constant LOANBOOK = address(0x10A4B00c0fFEe0000000000000000000000B0057);
    address internal constant IMPOSTOR = address(0xbAdc0dE000000000000000000000000000000BAd);
    uint64 internal constant SEPOLIA_KEY = 1;
    uint64 internal constant MAINNET_KEY = 3;

    address internal borrower = makeAddr("borrower");
    address internal relayer = makeAddr("relayer");

    uint256 internal constant PRINCIPAL = 0.002 ether;

    function setUp() public {
        MockNativeQueryVerifier deployed = new MockNativeQueryVerifier();
        vm.etch(NativeQueryVerifierLib.PRECOMPILE_ADDRESS, address(deployed).code);
        verifier = MockNativeQueryVerifier(NativeQueryVerifierLib.PRECOMPILE_ADDRESS);
        verifier.setShouldVerify(true);

        registry = new CreditRegistry();
        registry.registerSource(SEPOLIA_KEY, LOANBOOK, SourceKind.LoanBook);
        vm.warp(1_786_000_000);
    }

    // ─── Submission helpers ───────────────────────────────────────────────────────────────

    uint64 private _height = 11_482_800;

    /// @dev Submits a payload through the real `USCBase.execute` entrypoint. Each call uses a
    /// fresh merkle root so distinct submissions get distinct query ids.
    function _submit(uint8 action, uint64 chainKey, bytes memory payload, bytes32 salt) internal {
        INativeQueryVerifier.MerkleProofEntry[] memory siblings =
            new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: salt, isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));

        vm.prank(relayer);
        registry.execute(action, chainKey, _height, payload, salt, siblings, bytes32(uint256(0xab)), roots);
    }

    function _submit(bytes memory payload, bytes32 salt) internal {
        _submit(uint8(CreditRegistry.Action.Generic), SEPOLIA_KEY, payload, salt);
    }

    function _repayment(uint256 loanId, address who, uint256 amount, bool onTime)
        internal
        view
        returns (bytes memory)
    {
        return EncodedTxBuilder.single(
            EncodedTxBuilder.repaymentMade(LOANBOOK, EventSigs.REPAYMENT_MADE, loanId, who, amount, onTime)
        );
    }

    function _opened(uint256 loanId, address who, uint256 principal) internal view returns (bytes memory) {
        return EncodedTxBuilder.single(
            EncodedTxBuilder.loanOpened(LOANBOOK, EventSigs.LOAN_OPENED, loanId, who, principal, uint64(block.timestamp + 1 days))
        );
    }

    // ─── Happy paths ──────────────────────────────────────────────────────────────────────

    function test_ingest_repaymentUpdatesProfileAndScore() public {
        _submit(_repayment(1, borrower, PRINCIPAL, true), bytes32(uint256(1)));

        CreditProfile memory p = registry.profileOf(borrower);
        assertEq(p.onTime, 1);
        assertEq(p.late, 0);
        assertEq(p.totalRepaidWei, PRINCIPAL);
        assertGt(p.score, 0, "a verified repayment must move the score");
    }

    function test_ingest_lateRepaymentCountsAsLate() public {
        _submit(_repayment(1, borrower, PRINCIPAL, false), bytes32(uint256(2)));

        CreditProfile memory p = registry.profileOf(borrower);
        assertEq(p.late, 1);
        assertEq(p.onTime, 0);
    }

    function test_ingest_loanOpenedIncrementsCounter() public {
        _submit(uint8(CreditRegistry.Action.Generic), SEPOLIA_KEY, _opened(1, borrower, PRINCIPAL), bytes32(uint256(3)));
        assertEq(registry.profileOf(borrower).loansOpened, 1);
    }

    function test_ingest_collateralAccumulates() public {
        bytes memory payload = EncodedTxBuilder.single(
            EncodedTxBuilder.collateralAdded(LOANBOOK, EventSigs.COLLATERAL_ADDED, borrower, 0.003 ether)
        );
        _submit(uint8(CreditRegistry.Action.Generic), SEPOLIA_KEY, payload, bytes32(uint256(4)));

        assertEq(registry.profileOf(borrower).totalCollateralWei, 0.003 ether);
    }

    function test_ingest_loanClosesWhenRepaymentsCoverPrincipal() public {
        _submit(uint8(CreditRegistry.Action.Generic), SEPOLIA_KEY, _opened(7, borrower, PRINCIPAL), bytes32(uint256(10)));
        _submit(_repayment(7, borrower, PRINCIPAL / 2, true), bytes32(uint256(11)));
        assertEq(registry.profileOf(borrower).loansClosed, 0, "half repaid is not closed");

        _submit(_repayment(7, borrower, PRINCIPAL / 2, true), bytes32(uint256(12)));
        assertEq(registry.profileOf(borrower).loansClosed, 1);
    }

    /// @dev Each proof is independent, so the worker may prove a repayment before the loan
    /// opening it belongs to. Closure must still be derived correctly once both have landed.
    function test_ingest_outOfOrderProofsStillCloseLoan() public {
        _submit(_repayment(9, borrower, PRINCIPAL, true), bytes32(uint256(20)));
        assertEq(registry.profileOf(borrower).loansClosed, 0, "principal unknown yet");

        _submit(uint8(CreditRegistry.Action.Generic), SEPOLIA_KEY, _opened(9, borrower, PRINCIPAL), bytes32(uint256(21)));
        assertEq(registry.profileOf(borrower).loansClosed, 1, "closure reconciled once principal known");
    }

    /// @dev The reason we ingest every recognised log rather than routing on `action`: a query id
    /// identifies a transaction, so a second submission for the same tx is replay-blocked
    /// forever. Action-based routing would permanently lose the second event.
    function test_ingest_allEventsInOneTransaction() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = EncodedTxBuilder.loanOpened(
            LOANBOOK, EventSigs.LOAN_OPENED, 5, borrower, PRINCIPAL, uint64(block.timestamp + 1 days)
        );
        logs[1] = EncodedTxBuilder.repaymentMade(
            LOANBOOK, EventSigs.REPAYMENT_MADE, 5, borrower, PRINCIPAL, true
        );

        _submit(EncodedTxBuilder.encode(2, 1, logs), bytes32(uint256(30)));

        CreditProfile memory p = registry.profileOf(borrower);
        assertEq(p.loansOpened, 1, "opening ingested");
        assertEq(p.onTime, 1, "repayment ingested from the same transaction");
        assertEq(p.loansClosed, 1, "and the loan closed");
    }

    /// @dev Reputation must accrue to the borrower named in the proven log, never to whoever
    /// relayed the proof — otherwise a worker could farm credit for itself.
    function test_ingest_creditsBorrowerFromTopicNotRelayer() public {
        _submit(_repayment(1, borrower, PRINCIPAL, true), bytes32(uint256(40)));

        assertGt(registry.scoreOf(borrower), 0);
        assertEq(registry.scoreOf(relayer), 0, "relayer must gain nothing");
    }

    function test_ingest_emitsScoreUpdated() public {
        vm.recordLogs();
        _submit(_repayment(1, borrower, PRINCIPAL, true), bytes32(uint256(50)));

        bool found;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; ++i) {
            if (entries[i].topics[0] == keccak256("ScoreUpdated(address,uint16,uint16,uint8)")) found = true;
        }
        assertTrue(found, "ScoreUpdated must be emitted for the UI to react to");
    }

    // ─── Negative matrix — the substance ──────────────────────────────────────────────────

    /// @dev CC3 attests Ethereum Mainnet (chainKey 3) as well as Sepolia. A LoanBook look-alike
    /// deployed at the same address on mainnet would otherwise mint history here.
    /// @dev CC3 attests Ethereum mainnet as well as Sepolia. A LoanBook look-alike deployed at the
    /// same address on mainnet must not be able to mint history: the `(chainKey, emitter)` pair is
    /// unregistered there, so its logs are ignored and nothing is ingested.
    function test_reject_wrongSourceChain() public {
        bytes memory payload = _repayment(1, borrower, PRINCIPAL, true);

        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        _submit(uint8(CreditRegistry.Action.Generic), MAINNET_KEY, payload, bytes32(uint256(60)));
    }

    function test_reject_unregisteredEmitterOnRegisteredChain() public {
        bytes memory payload = EncodedTxBuilder.single(
            EncodedTxBuilder.repaymentMade(IMPOSTOR, EventSigs.REPAYMENT_MADE, 1, borrower, PRINCIPAL, true)
        );

        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        _submit(payload, bytes32(uint256(69)));
    }

    /// @dev The precompile proves inclusion, not success. A reverted repayment is still included
    /// in a block, and would otherwise count as a successful one.
    function test_reject_revertedSourceTransaction() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = EncodedTxBuilder.repaymentMade(
            LOANBOOK, EventSigs.REPAYMENT_MADE, 1, borrower, PRINCIPAL, true
        );

        vm.expectRevert(abi.encodeWithSelector(CreditRegistry.SourceTransactionFailed.selector, uint8(0)));
        _submit(EncodedTxBuilder.encode(2, 0, logs), bytes32(uint256(61)));
    }

    /// @dev `getLogsByEventSignature` filters on topic0 alone, so provenance is entirely our job.
    function test_reject_eventFromImpostorContract() public {
        bytes memory payload = EncodedTxBuilder.single(
            EncodedTxBuilder.repaymentMade(IMPOSTOR, EventSigs.REPAYMENT_MADE, 1, borrower, PRINCIPAL, true)
        );

        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        _submit(payload, bytes32(uint256(62)));
    }

    function test_reject_unknownEventSignature() public {
        bytes memory payload = EncodedTxBuilder.single(
            EncodedTxBuilder.repaymentMade(LOANBOOK, keccak256("SomethingElse(uint256)"), 1, borrower, PRINCIPAL, true)
        );

        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        _submit(payload, bytes32(uint256(63)));
    }

    /// @dev One source transaction, one ingest — otherwise a single genuine repayment could be
    /// resubmitted to farm an arbitrary score.
    function test_reject_replayedQuery() public {
        bytes32 salt = bytes32(uint256(64));
        bytes memory payload = _repayment(1, borrower, PRINCIPAL, true);

        _submit(payload, salt);
        uint16 scoreAfterFirst = registry.scoreOf(borrower);

        vm.expectRevert("Query already processed");
        _submit(payload, salt);

        assertEq(registry.scoreOf(borrower), scoreAfterFirst, "score must not double-count");
    }

    function test_reject_forgedProof() public {
        bytes memory payload = _repayment(1, borrower, PRINCIPAL, true);
        verifier.setShouldVerify(false);

        vm.expectRevert(MockNativeQueryVerifier.MockProofRejected.selector);
        _submit(payload, bytes32(uint256(65)));

        assertEq(registry.scoreOf(borrower), 0);
    }

    function test_reject_unknownAction() public {
        bytes memory payload = _repayment(1, borrower, PRINCIPAL, true);

        vm.expectRevert(abi.encodeWithSelector(CreditRegistry.UnknownAction.selector, uint8(9)));
        _submit(9, SEPOLIA_KEY, payload, bytes32(uint256(66)));
    }

    function test_reject_whenPaused() public {
        bytes memory payload = _repayment(1, borrower, PRINCIPAL, true);
        registry.pause();

        vm.expectRevert();
        _submit(payload, bytes32(uint256(67)));
    }

    function test_pause_onlyOwner() public {
        vm.prank(relayer);
        vm.expectRevert();
        registry.pause();
    }

    function test_unpause_resumesIngestion() public {
        registry.pause();
        registry.unpause();
        _submit(_repayment(1, borrower, PRINCIPAL, true), bytes32(uint256(68)));
        assertGt(registry.scoreOf(borrower), 0);
    }

    function test_registerSource_rejectsZeroEmitter() public {
        vm.expectRevert(CreditRegistry.ZeroAddress.selector);
        registry.registerSource(SEPOLIA_KEY, address(0), SourceKind.LoanBook);
    }

    function test_registerSource_isOwnerOnly() public {
        vm.prank(relayer);
        vm.expectRevert();
        registry.registerSource(SEPOLIA_KEY, IMPOSTOR, SourceKind.LoanBook);
    }

    /// @dev Removing a source must stop new ingestion without rewriting history already proven.
    function test_removeSource_stopsFurtherIngestion() public {
        _submit(_repayment(1, borrower, PRINCIPAL, true), bytes32(uint256(70)));
        uint16 scoreBefore = registry.scoreOf(borrower);
        assertGt(scoreBefore, 0);

        registry.removeSource(SEPOLIA_KEY, LOANBOOK);

        bytes memory payload = _repayment(2, borrower, PRINCIPAL, true);
        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        _submit(payload, bytes32(uint256(71)));

        assertEq(registry.scoreOf(borrower), scoreBefore, "already-proven history is untouched");
    }
}
