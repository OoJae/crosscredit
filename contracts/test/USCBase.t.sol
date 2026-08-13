// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {USCBase} from "../src/vendored/USCBase.sol";
import {INativeQueryVerifier, NativeQueryVerifierLib} from "../src/vendored/VerifierInterface.sol";
import {MockNativeQueryVerifier} from "./mocks/MockNativeQueryVerifier.sol";

/// @dev Minimal implementation that records what the hook received, so the tests can assert on
/// the base's behaviour without dragging in CreditRegistry's business logic.
contract HookSpy is USCBase {
    uint8 public lastAction;
    bytes32 public lastQueryId;
    uint64 public lastChainKey;
    bytes public lastPayload;
    uint256 public hookCalls;

    function _processAndEmitEvent(uint8 action, bytes32 queryId, uint64 chainKey, bytes memory encodedTransaction)
        internal
        override
    {
        lastAction = action;
        lastQueryId = queryId;
        lastChainKey = chainKey;
        lastPayload = encodedTransaction;
        ++hookCalls;
    }
}

/// @notice Characterisation tests for the vendored {USCBase}.
/// @dev These pin the behaviour CrossCredit's security rests on — replay protection, the
/// chainKey passthrough we added, and the revert-on-bad-proof contract — so that a future
/// re-vendor from upstream cannot silently change it.
contract USCBaseTest is Test {
    HookSpy internal spy;
    MockNativeQueryVerifier internal verifier;

    bytes internal constant PAYLOAD = hex"deadbeef";
    uint64 internal constant SEPOLIA_CHAIN_KEY = 1;
    uint64 internal constant BLOCK_HEIGHT = 11_482_570;

    function setUp() public {
        // Install the mock at the precompile's real address so USCBase's own constructor wiring
        // (NativeQueryVerifierLib.getVerifier) resolves to it — the contract under test is the
        // genuine vendored code, unmodified for testing.
        MockNativeQueryVerifier deployed = new MockNativeQueryVerifier();
        vm.etch(NativeQueryVerifierLib.PRECOMPILE_ADDRESS, address(deployed).code);
        verifier = MockNativeQueryVerifier(NativeQueryVerifierLib.PRECOMPILE_ADDRESS);
        verifier.setShouldVerify(true);

        spy = new HookSpy();
    }

    function _siblings(bytes32 seed) internal pure returns (INativeQueryVerifier.MerkleProofEntry[] memory entries) {
        entries = new INativeQueryVerifier.MerkleProofEntry[](1);
        entries[0] = INativeQueryVerifier.MerkleProofEntry({hash: seed, isLeft: true});
    }

    function _execute(bytes32 merkleRoot) internal returns (bool) {
        bytes32[] memory continuityRoots = new bytes32[](1);
        continuityRoots[0] = bytes32(uint256(0xc0));
        return spy.execute(
            7, SEPOLIA_CHAIN_KEY, BLOCK_HEIGHT, PAYLOAD, merkleRoot, _siblings(merkleRoot), bytes32(uint256(0xab)), continuityRoots
        );
    }

    function test_execute_runsHookWithVerifiedPayload() public {
        assertTrue(_execute(bytes32(uint256(1))));

        assertEq(spy.hookCalls(), 1);
        assertEq(spy.lastAction(), 7);
        assertEq(spy.lastPayload(), PAYLOAD);
    }

    /// @dev The reason we modified upstream: without chainKey the hook cannot tell Sepolia
    /// (key 1) from Ethereum Mainnet (key 3), both of which CC3 attests.
    function test_execute_forwardsChainKeyToHook() public {
        _execute(bytes32(uint256(2)));
        assertEq(spy.lastChainKey(), SEPOLIA_CHAIN_KEY);
    }

    function test_execute_marksQueryProcessed() public {
        _execute(bytes32(uint256(3)));
        assertTrue(spy.processedQueries(spy.lastQueryId()));
    }

    function test_execute_revertsOnReplayedQuery() public {
        bytes32 root = bytes32(uint256(4));
        _execute(root);

        vm.expectRevert("Query already processed");
        _execute(root);
    }

    /// @dev Distinct proofs must not collide, or one source transaction could block another.
    function test_execute_distinctProofsYieldDistinctQueryIds() public {
        _execute(bytes32(uint256(5)));
        bytes32 first = spy.lastQueryId();

        _execute(bytes32(uint256(6)));
        assertTrue(spy.lastQueryId() != first);
        assertEq(spy.hookCalls(), 2);
    }

    /// @dev The precompile reverts rather than returning false on a bad proof. Assert the hook
    /// never runs, and that the query id is left unconsumed for a later legitimate proof.
    function test_execute_revertsAndSkipsHookOnRejectedProof() public {
        verifier.setShouldVerify(false);

        vm.expectRevert(MockNativeQueryVerifier.MockProofRejected.selector);
        _execute(bytes32(uint256(7)));

        assertEq(spy.hookCalls(), 0);
    }

    /// @dev A rejected proof must not burn its query id — otherwise a forged submission could
    /// permanently censor a real transaction.
    function test_rejectedProofDoesNotConsumeQueryId() public {
        bytes32 root = bytes32(uint256(8));

        verifier.setShouldVerify(false);
        vm.expectRevert(MockNativeQueryVerifier.MockProofRejected.selector);
        _execute(root);

        verifier.setShouldVerify(true);
        assertTrue(_execute(root));
        assertEq(spy.hookCalls(), 1);
    }

    function test_verifierWiredToPrecompileAddress() public view {
        assertEq(address(spy.VERIFIER()), NativeQueryVerifierLib.PRECOMPILE_ADDRESS);
        assertEq(NativeQueryVerifierLib.PRECOMPILE_ADDRESS, address(0xFD2));
    }
}
