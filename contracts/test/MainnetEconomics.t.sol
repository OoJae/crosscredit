// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";
import {CreditRegistry} from "../src/creditcoin/CreditRegistry.sol";
import {CreditProfile, Tier} from "../src/creditcoin/ScoreLib.sol";
import {INativeQueryVerifier, NativeQueryVerifierLib} from "../src/vendored/VerifierInterface.sol";
import {MockNativeQueryVerifier} from "./mocks/MockNativeQueryVerifier.sol";
import {EncodedTxBuilder} from "./helpers/EncodedTxBuilder.sol";
import {SourceKind, EventSigs} from "../src/creditcoin/SourceKinds.sol";

/// @notice The economics of mainnet ingestion: what does and does not buy borrowing capacity.
///
/// @dev These are synthetic payloads on purpose. The captured-fixture suite in `MainnetProof.t.sol`
/// proves we decode *real* Aave transactions correctly; it cannot prove anything about transaction
/// shapes that no captured fixture happens to contain. Every rule below was unreachable from a
/// fixture, and every one of them is load-bearing:
///
///   - a repayment funded by a borrow in the same transaction (a flash loan) buys no capacity;
///   - a transaction carrying five repayments counts as one repayment, not five;
///   - capacity is the largest single repayment, never the running total.
///
/// The first two were live defects. Together they let one transaction, with **zero capital at
/// risk**, mint an arbitrary capacity and reach Platinum from a single proof — defeating the cap
/// that every other control in this system depends on.
contract MainnetEconomicsTest is Test {
    CreditRegistry internal registry;
    MockNativeQueryVerifier internal verifier;

    /// @dev Real mainnet addresses so the test reads against the deployment it models.
    address internal constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant SPARKLEND = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant UNREGISTERED = address(0xDEADBEEF);

    uint64 internal constant MAINNET_KEY = 3;
    uint64 internal constant NOW = 1_786_000_000;

    address internal borrower = makeAddr("mainnetBorrower");
    address internal relayer = makeAddr("relayer");

    uint64 private _height = 21_000_000;
    uint256 private _salt;

    function setUp() public {
        MockNativeQueryVerifier deployed = new MockNativeQueryVerifier();
        vm.etch(NativeQueryVerifierLib.PRECOMPILE_ADDRESS, address(deployed).code);
        verifier = MockNativeQueryVerifier(NativeQueryVerifierLib.PRECOMPILE_ADDRESS);
        verifier.setShouldVerify(true);

        registry = new CreditRegistry();
        registry.registerSource(MAINNET_KEY, AAVE_POOL, SourceKind.AaveV3);
        registry.registerSource(MAINNET_KEY, SPARKLEND, SourceKind.AaveV3);
        registry.registerReserve(USDT, 6);

        vm.warp(NOW);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────────────

    function _submit(bytes memory payload) internal {
        bytes32 salt = bytes32(++_salt);
        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: salt, isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));

        vm.prank(relayer);
        registry.execute(
            uint8(CreditRegistry.Action.Generic),
            MAINNET_KEY,
            _height,
            payload,
            salt,
            siblings,
            bytes32(uint256(0xab)),
            roots
        );
    }

    function _repayLog(uint256 amount) internal pure returns (EvmV1Decoder.LogEntryTuple memory) {
        return EncodedTxBuilder.aaveRepay(AAVE_POOL, EventSigs.AAVE_REPAY, USDT, _borrower(), _borrower(), amount);
    }

    function _borrower() internal pure returns (address) {
        // `makeAddr` is not pure; pin the address so log builders can stay pure.
        return 0x63C0E37B9eF2CE2BC53e20d19D40E4e1A6f22f2b;
    }

    function _capacity() internal view returns (uint256) {
        return registry.demonstratedCapacityOf(_borrower());
    }

    function _profile() internal view returns (CreditProfile memory) {
        return registry.profileOf(_borrower());
    }

    // ─── The flash-loan guard ─────────────────────────────────────────────────────────────

    /// A borrow and a repayment of the same asset, for the same account, in the same transaction
    /// is a flash loan: the money was never the borrower's and was never at risk. It is still a
    /// genuine repayment, so it counts as one — it just proves no capacity.
    function test_flashLoan_sameTransactionBorrowAndRepayGrantsNoCapacity() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = EncodedTxBuilder.aaveBorrow(AAVE_POOL, EventSigs.AAVE_BORROW, USDT, _borrower(), 8_000_000e6);
        logs[1] = _repayLog(8_000_000e6);

        _submit(EncodedTxBuilder.encode(2, 1, logs));

        assertEq(_capacity(), 0, "a flash loan must buy no borrowing capacity");
        assertEq(_profile().mainnetRepayments, 1, "it is still a real repayment");
    }

    /// The control. Identical amounts, identical asset, identical account — the only difference is
    /// that the borrow happened in a different transaction, so the debt was genuinely carried.
    function test_flashLoan_separateTransactionsDoGrantCapacity() public {
        EvmV1Decoder.LogEntryTuple[] memory borrowOnly = new EvmV1Decoder.LogEntryTuple[](1);
        borrowOnly[0] = EncodedTxBuilder.aaveBorrow(AAVE_POOL, EventSigs.AAVE_BORROW, USDT, _borrower(), 800e6);
        _submit(EncodedTxBuilder.encode(2, 1, borrowOnly));

        _submit(EncodedTxBuilder.single(_repayLog(800e6)));

        assertEq(_capacity(), 800e18, "a genuinely carried debt demonstrates capacity");
    }

    /// The guard must be specific. Repaying USDT while borrowing an unrelated asset is ordinary
    /// portfolio management, not a flash loan, and must not be penalised.
    function test_flashLoan_borrowOfADifferentReserveDoesNotSuppressCapacity() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = EncodedTxBuilder.aaveBorrow(AAVE_POOL, EventSigs.AAVE_BORROW, UNREGISTERED, _borrower(), 5e18);
        logs[1] = _repayLog(800e6);

        _submit(EncodedTxBuilder.encode(2, 1, logs));

        assertEq(_capacity(), 800e18, "an unrelated borrow is not a flash loan");
    }

    /// Likewise a borrow on behalf of someone else.
    function test_flashLoan_borrowForADifferentAccountDoesNotSuppressCapacity() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = EncodedTxBuilder.aaveBorrow(AAVE_POOL, EventSigs.AAVE_BORROW, USDT, address(0xFEED), 900e6);
        logs[1] = _repayLog(800e6);

        _submit(EncodedTxBuilder.encode(2, 1, logs));

        assertEq(_capacity(), 800e18, "someone else's borrow is not this borrower's flash loan");
    }

    /// The pre-scan authenticates the emitter like everything else: a borrow log from an
    /// unregistered contract is not evidence of anything and must not suppress a real repayment.
    function test_flashLoan_borrowFromAnUnregisteredEmitterIsIgnored() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = EncodedTxBuilder.aaveBorrow(IMPOSTOR(), EventSigs.AAVE_BORROW, USDT, _borrower(), 800e6);
        logs[1] = _repayLog(800e6);

        _submit(EncodedTxBuilder.encode(2, 1, logs));

        assertEq(_capacity(), 800e18, "an impostor cannot suppress a genuine repayment either");
    }

    function IMPOSTOR() internal pure returns (address) {
        return address(0xbAdc0dE000000000000000000000000000000BAd);
    }

    // ─── One repayment credit per transaction ─────────────────────────────────────────────

    /// Five `Repay` logs in one transaction used to award five repayments — 600 points, the whole
    /// mainnet term, from a single proof. Combined with the flash-loan hole that was Platinum for
    /// the price of gas.
    function test_perTransaction_manyRepayLogsCountOnce() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](5);
        for (uint256 i = 0; i < 5; ++i) {
            logs[i] = _repayLog(100e6);
        }

        _submit(EncodedTxBuilder.encode(2, 1, logs));

        assertEq(_profile().mainnetRepayments, 1, "one proven transaction is one repayment");
    }

    /// And the corollary: five separate transactions really are five repayments.
    function test_perTransaction_separateTransactionsCountSeparately() public {
        for (uint256 i = 0; i < 5; ++i) {
            _submit(EncodedTxBuilder.single(_repayLog(100e6)));
        }

        assertEq(_profile().mainnetRepayments, 5);
    }

    /// A single transaction cannot reach Platinum on its own, which is the property the
    /// per-transaction cap exists to guarantee.
    function test_perTransaction_oneTransactionCannotReachPlatinum() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](5);
        for (uint256 i = 0; i < 5; ++i) {
            logs[i] = _repayLog(1_000_000e6);
        }

        _submit(EncodedTxBuilder.encode(2, 1, logs));

        assertTrue(registry.tierOf(_borrower()) != Tier.Platinum, "one proof must not buy the top tier");
    }

    // ─── Capacity is a high-water mark ────────────────────────────────────────────────────

    /// Repaying 1 ETH a hundred times demonstrates the ability to handle 1 ETH, not 100. This rule
    /// is what makes capacity invariant under splitting a history across wallets, and until now
    /// nothing tested it — a mutant summing the repayments survived the entire suite.
    function test_capacity_isLargestSingleRepaymentNotTheSum() public {
        _submit(EncodedTxBuilder.single(_repayLog(5e6)));
        _submit(EncodedTxBuilder.single(_repayLog(800e6)));
        _submit(EncodedTxBuilder.single(_repayLog(20e6)));

        assertEq(_capacity(), 800e18, "capacity is the maximum, not the total");
    }

    /// A later, smaller repayment must not erode capacity already demonstrated.
    function test_capacity_isNotLoweredByASmallerLaterRepayment() public {
        _submit(EncodedTxBuilder.single(_repayLog(800e6)));
        assertEq(_capacity(), 800e18);

        _submit(EncodedTxBuilder.single(_repayLog(1e6)));
        assertEq(_capacity(), 800e18, "capacity ratchets upward only");
    }

    // ─── Unregistered reserves fail loud ──────────────────────────────────────────────────

    /// Ingesting a repayment of an unknown asset for zero capacity consumed the transaction's
    /// query id forever, so the proof could never be resubmitted after the owner registered the
    /// asset. That destroyed the borrower's largest repayment instead of deferring it — and let
    /// anyone front-run a victim's own import to cap them at zero permanently.
    function test_unregisteredReserve_revertsSoTheProofStaysRetryable() public {
        bytes memory payload = EncodedTxBuilder.single(
            EncodedTxBuilder.aaveRepay(AAVE_POOL, EventSigs.AAVE_REPAY, UNREGISTERED, _borrower(), _borrower(), 900e6)
        );

        vm.expectRevert(abi.encodeWithSelector(CreditRegistry.UnregisteredReserve.selector, UNREGISTERED));
        _submit(payload);
    }

    /// The point of failing loud: register the reserve and the same history now imports.
    function test_unregisteredReserve_worksOnceRegistered() public {
        registry.registerReserve(UNREGISTERED, 6);
        _submit(
            EncodedTxBuilder.single(
                EncodedTxBuilder.aaveRepay(
                    AAVE_POOL, EventSigs.AAVE_REPAY, UNREGISTERED, _borrower(), _borrower(), 900e6
                )
            )
        );

        assertEq(_capacity(), 900e18);
    }

    // ─── Sparklend shares Aave's shapes ───────────────────────────────────────────────────

    function test_sparklend_isDecodedByTheSameRules() public {
        _submit(
            EncodedTxBuilder.single(
                EncodedTxBuilder.aaveRepay(SPARKLEND, EventSigs.AAVE_REPAY, USDT, _borrower(), _borrower(), 300e6)
            )
        );

        assertEq(_capacity(), 300e18, "an Aave V3 fork is read by the same decoder");
    }

    /// The flash-loan guard matches on the emitter too, so a borrow on Aave and a repay on
    /// Sparklend are correctly treated as unrelated.
    function test_sparklend_borrowOnADifferentPoolDoesNotSuppressCapacity() public {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](2);
        logs[0] = EncodedTxBuilder.aaveBorrow(AAVE_POOL, EventSigs.AAVE_BORROW, USDT, _borrower(), 300e6);
        logs[1] = EncodedTxBuilder.aaveRepay(SPARKLEND, EventSigs.AAVE_REPAY, USDT, _borrower(), _borrower(), 300e6);

        _submit(EncodedTxBuilder.encode(2, 1, logs));

        assertEq(_capacity(), 300e18, "different pools are different debts");
    }
}
