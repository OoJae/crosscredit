// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";
import {CreditRegistry} from "../src/creditcoin/CreditRegistry.sol";
import {CreditProfile, ScoreLib, Tier} from "../src/creditcoin/ScoreLib.sol";
import {INativeQueryVerifier, NativeQueryVerifierLib} from "../src/vendored/VerifierInterface.sol";
import {MockNativeQueryVerifier} from "./mocks/MockNativeQueryVerifier.sol";

/// @notice Decodes **real** Attestcoin proofs captured from the live CC3 prover.
///
/// @dev Every other test in this repo feeds the registry payloads we constructed ourselves, which
/// only proves our decoder agrees with our encoder. These tests feed it `txBytes` produced by
/// Gluwa's prover for transactions that actually happened on Sepolia — the same bytes the
/// precompile verifies in production. If the Attestcoin encoding differs from our understanding
/// in any way, these fail and the synthetic tests would not.
///
/// The fixtures were captured by `scripts/capture-proof.ts` against
/// `docs/evidence/seeded-history.json` and cost nothing: the blocks were already attested, and
/// fetching a proof is a read.
///
/// The verifier is still mocked, because the block-prover precompile only exists on Creditcoin —
/// but the **decoding and the entire validation chain are real**.
contract RealProofTest is Test {
    /// @dev The live Sepolia LoanBook that emitted these logs.
    address internal constant LOANBOOK = 0xE53a54489AEC265337F6f8Fa3EE6e08EcbA5Cf9c;
    address internal constant BORROWER_A = 0x8ce707293F8BDE083A09B86CbB70d6a20F0F89c6;
    address internal constant BORROWER_B = 0x04163f60FA50519D86AeFB8e450312bAD76CA0B6;
    uint64 internal constant SEPOLIA_KEY = 1;

    CreditRegistry internal registry;
    MockNativeQueryVerifier internal verifier;

    function setUp() public {
        MockNativeQueryVerifier deployed = new MockNativeQueryVerifier();
        vm.etch(NativeQueryVerifierLib.PRECOMPILE_ADDRESS, address(deployed).code);
        verifier = MockNativeQueryVerifier(NativeQueryVerifierLib.PRECOMPILE_ADDRESS);
        verifier.setShouldVerify(true);

        registry = new CreditRegistry(SEPOLIA_KEY, LOANBOOK);
    }

    function _txBytes(string memory fixture) internal view returns (bytes memory) {
        string memory json = vm.readFile(string.concat("contracts/test/fixtures/", fixture));
        return vm.parseJsonBytes(json, ".proof.txBytes");
    }

    function _height(string memory fixture) internal view returns (uint64) {
        string memory json = vm.readFile(string.concat("contracts/test/fixtures/", fixture));
        return uint64(vm.parseJsonUint(json, ".proof.headerNumber"));
    }

    function _submit(bytes memory payload, uint64 height, bytes32 salt) internal {
        INativeQueryVerifier.MerkleProofEntry[] memory siblings =
            new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: salt, isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));

        registry.execute(
            uint8(CreditRegistry.Action.RepaymentMade),
            SEPOLIA_KEY,
            height,
            payload,
            salt,
            siblings,
            bytes32(uint256(0xab)),
            roots
        );
    }

    // ─── The encoding itself ──────────────────────────────────────────────────────────────

    /// @dev Sepolia is post-London, so real transactions are type 2 (EIP-1559) — three chunks
    /// with the receipt at index 2.
    function test_realProof_isTypeTwoTransaction() public view {
        uint8 txType = EvmV1Decoder.getTransactionType(_txBytes("repayment-ontime.json"));
        assertEq(txType, 2, "Sepolia repayments should encode as EIP-1559 type 2");
        assertTrue(EvmV1Decoder.isValidTransactionType(txType));
    }

    function test_realProof_receiptDecodesAsSuccessful() public view {
        EvmV1Decoder.ReceiptFields memory receipt =
            EvmV1Decoder.decodeReceiptFields(_txBytes("repayment-ontime.json"));

        assertEq(receipt.receiptStatus, 1, "the seeded repayment succeeded on Sepolia");
        assertGt(receipt.receiptLogs.length, 0, "it emitted at least one log");
    }

    /// @dev Confirms the wire format `LoanBook.t.sol` asserts locally survives the round trip
    /// through Sepolia, the prover's encoding, and our decoder.
    function test_realProof_logMatchesOurWireFormat() public view {
        EvmV1Decoder.ReceiptFields memory receipt =
            EvmV1Decoder.decodeReceiptFields(_txBytes("repayment-ontime.json"));

        EvmV1Decoder.LogEntry memory log = receipt.receiptLogs[0];
        assertEq(log.address_, LOANBOOK, "emitted by our LoanBook");
        assertEq(log.topics.length, 3, "sig + loanId + borrower");
        assertEq(log.topics[0], registry.REPAYMENT_MADE_SIG());
        assertEq(address(uint160(uint256(log.topics[2]))), BORROWER_A);
        assertEq(log.data.length, 96, "amount + onTime + timestamp");

        (uint256 amount, bool onTime,) = abi.decode(log.data, (uint256, bool, uint64));
        assertEq(amount, 0.001 ether);
        assertTrue(onTime);
    }

    // ─── Full ingest through the real validation chain ────────────────────────────────────

    function test_realProof_ingestsAndScoresBorrower() public {
        _submit(_txBytes("repayment-ontime.json"), _height("repayment-ontime.json"), bytes32(uint256(1)));

        CreditProfile memory p = registry.profileOf(BORROWER_A);
        assertEq(p.onTime, 1);
        assertEq(p.late, 0);
        assertEq(p.totalRepaidWei, 0.001 ether);
        assertGt(p.score, 0, "a real proven Sepolia repayment moves the score");
    }

    /// @dev The late flag is stamped by `LoanBook` on Sepolia using that chain's clock, carried
    /// through the proof, and read back here. Creditcoin has no way to re-derive it.
    function test_realProof_lateRepaymentArrivesFlaggedLate() public {
        _submit(_txBytes("repayment-late.json"), _height("repayment-late.json"), bytes32(uint256(2)));

        CreditProfile memory p = registry.profileOf(BORROWER_B);
        assertEq(p.late, 1, "Borrower B's real late repayment must be recorded as late");
        assertEq(p.onTime, 0);
        assertEq(uint8(registry.tierOf(BORROWER_B)), uint8(Tier.Bronze));
    }

    function test_realProof_twoRepaymentsAccumulate() public {
        _submit(_txBytes("repayment-ontime.json"), _height("repayment-ontime.json"), bytes32(uint256(3)));
        _submit(
            _txBytes("repayment-closes-loan.json"), _height("repayment-closes-loan.json"), bytes32(uint256(4))
        );

        CreditProfile memory p = registry.profileOf(BORROWER_A);
        assertEq(p.onTime, 2);
        assertEq(p.totalRepaidWei, 0.002 ether);
    }

    /// @dev Real proof, wrong chain: the payload is genuine and the transaction really happened,
    /// but claiming it came from Ethereum Mainnet (chainKey 3) must still be rejected.
    function test_realProof_rejectedWhenChainKeyIsWrong() public {
        bytes memory payload = _txBytes("repayment-ontime.json");
        uint64 height = _height("repayment-ontime.json");

        INativeQueryVerifier.MerkleProofEntry[] memory siblings =
            new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: bytes32(uint256(5)), isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));

        vm.expectRevert(abi.encodeWithSelector(CreditRegistry.WrongSourceChain.selector, SEPOLIA_KEY, uint64(3)));
        registry.execute(
            uint8(CreditRegistry.Action.RepaymentMade),
            3,
            height,
            payload,
            bytes32(uint256(5)),
            siblings,
            bytes32(uint256(0xab)),
            roots
        );
    }

    /// @dev Real proof, wrong registry: a registry watching a different LoanBook must ignore
    /// these logs entirely, even though the proof is perfectly valid.
    function test_realProof_rejectedByRegistryWatchingAnotherLoanBook() public {
        CreditRegistry other = new CreditRegistry(SEPOLIA_KEY, address(0xdeadbeef));

        // Read the fixture before `expectRevert`: vm.readFile is itself a cheatcode call.
        bytes memory payload = _txBytes("repayment-ontime.json");
        uint64 height = _height("repayment-ontime.json");

        INativeQueryVerifier.MerkleProofEntry[] memory siblings =
            new INativeQueryVerifier.MerkleProofEntry[](1);
        siblings[0] = INativeQueryVerifier.MerkleProofEntry({hash: bytes32(uint256(6)), isLeft: true});
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(0xc0));

        vm.expectRevert(CreditRegistry.NoRecognisedEvents.selector);
        other.execute(
            uint8(CreditRegistry.Action.RepaymentMade),
            SEPOLIA_KEY,
            height,
            payload,
            bytes32(uint256(6)),
            siblings,
            bytes32(uint256(0xab)),
            roots
        );
    }
}
