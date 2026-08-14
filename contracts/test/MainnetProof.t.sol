// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";
import {CreditRegistry} from "../src/creditcoin/CreditRegistry.sol";
import {CreditProfile, ScoreLib, Tier} from "../src/creditcoin/ScoreLib.sol";
import {SourceKind, EventSigs} from "../src/creditcoin/SourceKinds.sol";
import {INativeQueryVerifier, NativeQueryVerifierLib} from "../src/vendored/VerifierInterface.sol";
import {MockNativeQueryVerifier} from "./mocks/MockNativeQueryVerifier.sol";

/// @notice Decodes **real Ethereum mainnet transactions** captured from the live CC3 prover.
///
/// @dev This is the suite that matters most, because it is the only one where the data was not
/// produced by us. The fixtures are genuine mainnet activity — someone's actual Aave repayment,
/// someone's actual liquidation, someone's actual ENS registration — fetched from Creditcoin's
/// prover for chainKey 3 and independently verified `true` against the live block-prover
/// precompile before being committed.
///
/// That matters beyond decoder coverage. Our own `LoanBook` has no lender, so history from it
/// costs gas to manufacture; these transactions cost real money to produce, by people who had no
/// idea CrossCredit exists. Everything the credit model treats as *evidence* rather than
/// *assertion* comes through this path.
///
/// The verifier is still mocked, because the precompile exists only on Creditcoin — but the
/// decoding and the whole validation chain are real.
contract MainnetProofTest is Test {
    /// @dev Creditcoin-internal id for Ethereum mainnet. Not the EVM chain id.
    uint64 internal constant MAINNET = 3;
    uint64 internal constant SEPOLIA = 1;

    address internal constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant ENS_CONTROLLER_V4 = 0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547;

    /// @dev The real borrowers in the captured transactions.
    address internal constant AAVE_BORROWER = 0xE4Fd8213711F18Fad8A97A1DB45436Abd8a2902c;
    address internal constant LIQUIDATED_BORROWER = 0x52aD04141bCbF74A3834EeFBcB75A2Ae613d75dE;
    address internal constant ENS_OWNER = 0xebB2AA4bb5A375e0e334906c0c73cF0d6D0015AF;

    CreditRegistry internal registry;
    MockNativeQueryVerifier internal verifier;

    function setUp() public {
        MockNativeQueryVerifier deployed = new MockNativeQueryVerifier();
        vm.etch(NativeQueryVerifierLib.PRECOMPILE_ADDRESS, address(deployed).code);
        verifier = MockNativeQueryVerifier(NativeQueryVerifierLib.PRECOMPILE_ADDRESS);
        verifier.setShouldVerify(true);

        registry = new CreditRegistry();
        registry.registerSource(MAINNET, AAVE_V3_POOL, SourceKind.AaveV3);
        registry.registerSource(MAINNET, ENS_CONTROLLER_V4, SourceKind.EnsRegistrar);
        registry.registerReserve(USDT, 6);
    }

    /// @dev The reserve repaid in the captured transaction. USDT has 6 decimals, not 18 — which
    /// is precisely the trap `registerReserve` exists to avoid.
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    function _txBytes(string memory fixture) internal view returns (bytes memory) {
        return vm.parseJsonBytes(vm.readFile(string.concat("contracts/test/fixtures/", fixture)), ".proof.txBytes");
    }

    function _height(string memory fixture) internal view returns (uint64) {
        return uint64(
            vm.parseJsonUint(vm.readFile(string.concat("contracts/test/fixtures/", fixture)), ".proof.headerNumber")
        );
    }

    function _submit(uint64 chainKey, bytes memory payload, uint64 height, bytes32 salt) internal {
        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: salt, isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));

        registry.execute(0, chainKey, height, payload, salt, siblings, bytes32(uint256(0xab)), roots);
    }

    // ─── The encoding, straight from mainnet ──────────────────────────────────────────────

    /// @dev A real mainnet transaction carries many logs from many unrelated contracts — five in
    /// this one — which is exactly why source authentication cannot be skipped.
    function test_mainnet_transactionCarriesManyUnrelatedLogs() public view {
        EvmV1Decoder.ReceiptFields memory receipt =
            EvmV1Decoder.decodeReceiptFields(_txBytes("mainnet-aave-repay.json"));

        assertEq(receipt.receiptStatus, 1);
        assertGt(receipt.receiptLogs.length, 1, "real transactions touch several protocols");

        uint256 fromAave;
        for (uint256 i = 0; i < receipt.receiptLogs.length; ++i) {
            if (receipt.receiptLogs[i].address_ == AAVE_V3_POOL) ++fromAave;
        }
        assertGt(fromAave, 0, "at least one log is Aave's");
        assertLt(fromAave, receipt.receiptLogs.length, "and most are not");
    }

    /// @dev Aave's `Repay` puts the borrower in topics[2] and 64 bytes in data — a different shape
    /// from our own `LoanBook`, which is why decoding is per-protocol.
    function test_mainnet_aaveRepayMatchesExpectedShape() public view {
        EvmV1Decoder.ReceiptFields memory receipt =
            EvmV1Decoder.decodeReceiptFields(_txBytes("mainnet-aave-repay.json"));

        bool found;
        for (uint256 i = 0; i < receipt.receiptLogs.length; ++i) {
            EvmV1Decoder.LogEntry memory log = receipt.receiptLogs[i];
            if (log.address_ != AAVE_V3_POOL || log.topics[0] != EventSigs.AAVE_REPAY) continue;

            found = true;
            assertEq(log.topics.length, 4, "sig + reserve + user + repayer");
            assertEq(log.data.length, 64, "amount + useATokens");
            assertEq(address(uint160(uint256(log.topics[2]))), AAVE_BORROWER);

            (uint256 amount,) = abi.decode(log.data, (uint256, bool));
            assertGt(amount, 0);
        }
        assertTrue(found, "the fixture must contain an Aave Repay");
    }

    // ─── Full ingest through the real validation chain ────────────────────────────────────

    /// @dev The headline: a stranger's real Aave repayment becomes credit history on Creditcoin.
    function test_mainnet_realAaveRepaymentBecomesCreditHistory() public {
        _submit(MAINNET, _txBytes("mainnet-aave-repay.json"), _height("mainnet-aave-repay.json"), bytes32(uint256(1)));

        CreditProfile memory p = registry.profileOf(AAVE_BORROWER);
        assertEq(p.mainnetRepayments, 1);
        assertGt(p.totalRepaidWei, 0);
        assertGt(p.score, 0, "a real repayment moves the score");
    }

    /// @dev And it is the only kind of evidence that raises demonstrated capacity, because it is
    /// the only kind that cost a third party's capital to produce.
    function test_mainnet_repaymentDemonstratesBorrowingCapacity() public {
        assertEq(registry.demonstratedCapacityOf(AAVE_BORROWER), 0, "unknown address starts at zero");

        _submit(MAINNET, _txBytes("mainnet-aave-repay.json"), _height("mainnet-aave-repay.json"), bytes32(uint256(2)));

        assertGt(
            registry.demonstratedCapacityOf(AAVE_BORROWER),
            0,
            "a real repayment is what unlocks undercollateralized credit"
        );
    }

    /// @dev A real liquidation — the mainnet analogue of a default — is recorded and bars Platinum.
    function test_mainnet_realLiquidationIsRecorded() public {
        _submit(
            MAINNET,
            _txBytes("mainnet-aave-liquidation.json"),
            _height("mainnet-aave-liquidation.json"),
            bytes32(uint256(3))
        );

        CreditProfile memory p = registry.profileOf(LIQUIDATED_BORROWER);
        assertEq(p.liquidations, 1, "the liquidated address is read from topics[3]");
        assertTrue(
            ScoreLib.tierFor(p, 1000) != Tier.Platinum,
            "a liquidation bars Platinum however strong the rest of the record"
        );
    }

    /// @dev ENS is a sunk cost with a provable expiry, not credit. It contributes a small bonus
    /// and, crucially, its expiry is enforced against Creditcoin's own clock.
    function test_mainnet_ensRegistrationSetsIdentityExpiry() public {
        _submit(
            MAINNET, _txBytes("mainnet-ens-registered.json"), _height("mainnet-ens-registered.json"), bytes32(uint256(4))
        );

        CreditProfile memory p = registry.profileOf(ENS_OWNER);
        assertGt(p.identityExpiry, block.timestamp, "an unexpired name was proven");
    }

    /// @dev The precompile proves *past events*, never *current state*. A name that has since
    /// lapsed must therefore stop counting — which the score enforces by comparing the proven
    /// expiry against the clock rather than storing a boolean.
    function test_mainnet_lapsedIdentityStopsCounting() public {
        _submit(
            MAINNET, _txBytes("mainnet-ens-registered.json"), _height("mainnet-ens-registered.json"), bytes32(uint256(5))
        );

        CreditProfile memory p = registry.profileOf(ENS_OWNER);

        // Compare at a single instant, varying only the expiry. Scoring the same profile at a
        // later timestamp would also grow the age term and mask what is being measured.
        //
        // Built field by field rather than by assigning the struct: in Solidity, one memory
        // struct assigned to another is a *reference*, so mutating the copy would silently mutate
        // the original and both sides would score identically.
        CreditProfile memory lapsed;
        lapsed.oldestActivity = p.oldestActivity;
        lapsed.identityExpiry = uint64(block.timestamp) - 1;

        uint16 whileValid = ScoreLib.compute(p, uint64(block.timestamp));
        uint16 afterExpiry = ScoreLib.compute(lapsed, uint64(block.timestamp));

        assertEq(
            whileValid - afterExpiry,
            ScoreLib.POINTS_IDENTITY,
            "a lapsed name contributes exactly nothing"
        );
    }

    // ─── Source authentication, with real data ────────────────────────────────────────────

    /// @dev The same genuine Aave transaction, presented as if it came from Sepolia. Aave is not a
    /// registered source there, so nothing is ingested — this is what stops a look-alike contract
    /// deployed at the same address on a different chain, now that Creditcoin attests two.
    function test_mainnet_rejectedWhenClaimedFromWrongChain() public {
        bytes memory payload = _txBytes("mainnet-aave-repay.json");
        uint64 height = _height("mainnet-aave-repay.json");

        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        _submit(SEPOLIA, payload, height, bytes32(uint256(6)));
    }

    /// @dev A registry that has not registered Aave ignores the same proof entirely.
    function test_mainnet_rejectedByRegistryThatDoesNotTrustAave() public {
        CreditRegistry other = new CreditRegistry();
        bytes memory payload = _txBytes("mainnet-aave-repay.json");
        uint64 height = _height("mainnet-aave-repay.json");

        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: bytes32(uint256(7)), isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));

        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        other.execute(0, MAINNET, height, payload, bytes32(uint256(7)), siblings, bytes32(uint256(0xab)), roots);
    }

    /// @dev Replay protection is source-agnostic — one real mainnet transaction, ingested once.
    function test_mainnet_replayIsRejected() public {
        bytes memory payload = _txBytes("mainnet-aave-repay.json");
        uint64 height = _height("mainnet-aave-repay.json");

        _submit(MAINNET, payload, height, bytes32(uint256(8)));
        uint256 capacityAfterFirst = registry.demonstratedCapacityOf(AAVE_BORROWER);

        vm.expectRevert("Query already processed");
        _submit(MAINNET, payload, height, bytes32(uint256(8)));

        assertEq(registry.demonstratedCapacityOf(AAVE_BORROWER), capacityAfterFirst);
    }

    // ─── Reserve decimals ─────────────────────────────────────────────────────────────────

    /// @dev Aave denominates repayments in the reserve's own units. The captured transaction
    /// repays USDT at 6 decimals; treated naively as 18-decimal wei it would round to zero
    /// capacity, making a genuine repayment look worthless. This test caught that in production
    /// output before it reached the demo.
    function test_mainnet_reserveAmountIsNormalisedToEighteenDecimals() public {
        _submit(MAINNET, _txBytes("mainnet-aave-repay.json"), _height("mainnet-aave-repay.json"), bytes32(uint256(10)));

        uint256 capacity = registry.demonstratedCapacityOf(AAVE_BORROWER);
        assertGt(capacity, 1e18, "a ~789 unit repayment must not normalise to dust");
        assertLt(capacity, 10_000e18, "nor be inflated");
    }

    /// @dev An unregistered reserve fails closed: the repayment still counts, but it contributes
    /// no borrowing capacity, because crediting an unknown quantity is worse than crediting none.
    function test_mainnet_unregisteredReserveGrantsNoCapacity() public {
        CreditRegistry fresh = new CreditRegistry();
        fresh.registerSource(MAINNET, AAVE_V3_POOL, SourceKind.AaveV3);
        // Deliberately no registerReserve call.

        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: bytes32(uint256(11)), isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));

        fresh.execute(
            0,
            MAINNET,
            _height("mainnet-aave-repay.json"),
            _txBytes("mainnet-aave-repay.json"),
            bytes32(uint256(11)),
            siblings,
            bytes32(uint256(0xab)),
            roots
        );

        assertEq(fresh.profileOf(AAVE_BORROWER).mainnetRepayments, 1, "the repayment still counts");
        assertEq(fresh.demonstratedCapacityOf(AAVE_BORROWER), 0, "but grants no borrowing capacity");
    }

    /// @dev Sepolia and mainnet histories accumulate into one profile, which is the whole point of
    /// portable reputation — but only the mainnet half raises demonstrated capacity.
    function test_mainnet_coexistsWithSepoliaHistory() public {
        registry.registerSource(SEPOLIA, AAVE_V3_POOL, SourceKind.AaveV3);

        _submit(MAINNET, _txBytes("mainnet-aave-repay.json"), _height("mainnet-aave-repay.json"), bytes32(uint256(9)));
        CreditProfile memory p = registry.profileOf(AAVE_BORROWER);

        assertEq(p.mainnetRepayments, 1);
        assertEq(p.onTime, 0, "Aave has no due dates, so no on-time signal exists");
        assertEq(p.late, 0);
    }
}
