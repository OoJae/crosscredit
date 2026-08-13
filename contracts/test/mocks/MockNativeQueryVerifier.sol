// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {INativeQueryVerifier} from "../../src/vendored/VerifierInterface.sol";

/// @title MockNativeQueryVerifier
/// @notice Test double for Creditcoin's BlockProver precompile.
/// @dev Intended to be installed at the precompile's real address via `vm.etch`, so tests
/// exercise the genuine {USCBase} code path rather than a reimplementation of it.
///
/// TEST-ONLY. Nothing under `contracts/test/` is ever deployed — every user-facing path runs
/// against the real precompile on live CC3 testnet.
///
/// It mimics the two behaviours our contracts depend on:
///   1. `verify*` REVERTS on a bad proof (it never returns false) — matching the precompile's
///      documented contract, so tests catch code that wrongly branches on the return value.
///   2. `calculateTxIndex` derives an index from the Merkle path, giving distinct query ids for
///      distinct proofs so replay protection can be tested meaningfully.
contract MockNativeQueryVerifier is INativeQueryVerifier {
    /// @notice When false, every verification reverts — used to drive negative-path tests.
    bool public shouldVerify = true;

    /// @notice Overrides the index returned by {calculateTxIndex} when set.
    uint64 private _forcedTxIndex;
    bool private _txIndexForced;

    event TransactionVerifiedMock(uint64 chainKey, uint64 height, uint64 transactionIndex);

    error MockProofRejected();

    /// @notice Toggles whether proofs verify, so a test can simulate a forged proof.
    function setShouldVerify(bool value) external {
        shouldVerify = value;
    }

    /// @notice Pins {calculateTxIndex}'s result, letting a test force a query-id collision.
    function forceTxIndex(uint64 index) external {
        _forcedTxIndex = index;
        _txIndexForced = true;
    }

    /// @inheritdoc INativeQueryVerifier
    function verifyAndEmit(
        uint64 chainKey,
        uint64 height,
        bytes calldata,
        MerkleProof calldata merkleProof,
        ContinuityProof calldata
    ) external returns (bool) {
        if (!shouldVerify) revert MockProofRejected();
        emit TransactionVerifiedMock(chainKey, height, _txIndex(merkleProof));
        return true;
    }

    /// @inheritdoc INativeQueryVerifier
    function verify(uint64, uint64, bytes calldata, MerkleProof calldata, ContinuityProof calldata)
        external
        view
        returns (bool)
    {
        if (!shouldVerify) revert MockProofRejected();
        return true;
    }

    /// @inheritdoc INativeQueryVerifier
    function verifyAndEmit(
        uint64 chainKey,
        uint64[] calldata heights,
        bytes[] calldata encodedTransactions,
        MerkleProof[] calldata merkleProofs,
        ContinuityProof calldata
    ) external returns (bool) {
        if (!shouldVerify) revert MockProofRejected();
        // Mirror the precompile's documented batch limits so tests fail the same way it would.
        require(heights.length > 0 && heights.length <= 10, "MockVerifier: batch size");
        require(
            heights.length == encodedTransactions.length && heights.length == merkleProofs.length,
            "MockVerifier: length mismatch"
        );
        uint64 lowest = heights[0];
        uint64 highest = heights[0];
        for (uint256 i = 1; i < heights.length; ++i) {
            if (heights[i] < lowest) lowest = heights[i];
            if (heights[i] > highest) highest = heights[i];
        }
        require(highest - lowest < 1000, "MockVerifier: batch range");
        for (uint256 i = 0; i < heights.length; ++i) {
            emit TransactionVerifiedMock(chainKey, heights[i], _txIndex(merkleProofs[i]));
        }
        return true;
    }

    /// @inheritdoc INativeQueryVerifier
    function verify(uint64, uint64[] calldata, bytes[] calldata, MerkleProof[] calldata, ContinuityProof calldata)
        external
        view
        returns (bool)
    {
        if (!shouldVerify) revert MockProofRejected();
        return true;
    }

    /// @inheritdoc INativeQueryVerifier
    function calculateTxIndex(MerkleProof calldata merkleProof) external view returns (uint64) {
        return _txIndex(merkleProof);
    }

    /// @dev Derives a deterministic pseudo-index from the proof so different proofs yield
    /// different query ids. The real precompile reads it off the path's left/right turns.
    function _txIndex(MerkleProof memory merkleProof) private view returns (uint64) {
        if (_txIndexForced) return _forcedTxIndex;
        return uint64(uint256(keccak256(abi.encode(merkleProof.root, merkleProof.siblings.length))) % 1024);
    }
}
