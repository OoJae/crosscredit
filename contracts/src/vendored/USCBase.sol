// SPDX-License-Identifier: MIT
//
// ─── VENDORED, WITH ONE FUNCTIONAL MODIFICATION ──────────────────────────────────────────────
// Source:  gluwa/usc-testnet-bridge-examples — contracts/sol/USCBase.sol
// Commit:  4ff9a3bf5d7fa8dbfec34ae9726d3f81405dca7b  (2026-07-29)
// URL:     https://github.com/gluwa/usc-testnet-bridge-examples/blob/4ff9a3bf/contracts/sol/USCBase.sol
// License: MIT (upstream LICENSE)
//
// Why vendored: `USCBase` ships only inside the examples repository — it is not part of the
// published `@gluwa/usc-contracts` package, so there is nothing to import.
//
// MODIFICATIONS vs upstream:
//   1. `_processAndEmitEvent` gains a `uint64 chainKey` parameter (and `execute` forwards it).
//      Upstream drops chainKey after verification, but CC3 testnet attests TWO source chains —
//      Ethereum Sepolia (chainKey 1) and Ethereum Mainnet (chainKey 3), per
//      docs/evidence/supported-chains.json. Without chainKey in the hook, an implementation
//      cannot tell the two apart, so a contract sitting at the same address on Ethereum Mainnet
//      could emit look-alike events and have them accepted as Sepolia history. Source-chain
//      authentication is impossible without this value, and `execute` is `external` and
//      non-virtual, so it cannot be wrapped by a subclass instead.
//   2. Added NatSpec. No other logic, storage layout, or control flow is changed — the
//      verification path and the `_computeQueryId` assembly are byte-for-byte upstream so the
//      security-critical core stays diffable against the original.
// ─────────────────────────────────────────────────────────────────────────────────────────────
pragma solidity ^0.8.23;

import {INativeQueryVerifier, NativeQueryVerifierLib} from "./VerifierInterface.sol";

/// @title USCBase
/// @notice Base for an Attestcoin Smart Contract (ASC): verifies that a transaction really
/// happened on a supported source chain, guards against replaying the same proof, and hands the
/// verified payload to business logic.
/// @dev Subclasses implement {_processAndEmitEvent}. That hook runs only after the precompile has
/// confirmed inclusion and continuity — but the precompile does NOT check transaction success, so
/// the hook must decode the receipt and enforce `receiptStatus == 1` itself.
abstract contract USCBase {
    /// @notice The Native Query Verifier precompile instance
    /// @dev Address: 0x0000000000000000000000000000000000000FD2 (4050 decimal)
    INativeQueryVerifier public immutable VERIFIER;

    /// @notice Query ids already consumed, keyed by {_computeQueryId}. The replay guard.
    /// @dev A query id binds (chainKey, blockHeight, txIndex), so one source transaction can be
    /// ingested exactly once even if an attacker resubmits an otherwise valid proof.
    mapping(bytes32 => bool) public processedQueries;

    constructor() {
        // Get the precompile instance using the helper library
        VERIFIER = NativeQueryVerifierLib.getVerifier();
    }

    /// @notice Business-logic hook, invoked once per successfully verified transaction.
    /// @param action Caller-supplied selector telling the implementation how to interpret the
    /// payload. It is NOT attested — treat it as a hint and re-derive trust from the payload.
    /// @param queryId The replay-protection id, already marked consumed.
    /// @param chainKey Source chain the proof was verified against. MUST be checked by the
    /// implementation (see modification note 1 above).
    /// @param encodedTransaction The verified, Attestcoin-encoded transaction + receipt.
    function _processAndEmitEvent(
        uint8 action,
        bytes32 queryId,
        uint64 chainKey,
        bytes memory encodedTransaction
    ) internal virtual;

    /// @notice Verifies a source-chain transaction and runs the business-logic hook.
    /// @dev Order matters: replay-check, then verify, then mark consumed, then act. Marking
    /// before verification would let a failed proof burn a legitimate query id.
    /// @param merkleRoot The source block's transaction Merkle root.
    /// @param siblings Merkle path proving the transaction's inclusion under `merkleRoot`.
    /// @param lowerEndpointDigest Attested block anchoring the continuity proof.
    /// @param continuityRoots Block roots linking that anchor to `blockHeight`.
    /// @return success True when the transaction was verified and the hook ran.
    function execute(
        uint8 action,
        uint64 chainKey,
        uint64 blockHeight,
        bytes calldata encodedTransaction,
        bytes32 merkleRoot,
        INativeQueryVerifier.MerkleProofEntry[] calldata siblings,
        bytes32 lowerEndpointDigest,
        bytes32[] calldata continuityRoots
    ) external returns (bool success) {
        bytes32 queryId = _computeQueryId(chainKey, blockHeight, merkleRoot, siblings);

        require(!processedQueries[queryId], "Query already processed");

        // First we verify the proof
        bool verified = _verifyProof(
            chainKey, blockHeight, encodedTransaction, merkleRoot, siblings, lowerEndpointDigest, continuityRoots
        );
        require(verified, "Proof of inclusion verification failed");

        // Mark the query as processed
        processedQueries[queryId] = true;

        _processAndEmitEvent(action, queryId, chainKey, encodedTransaction);

        return true;
    }

    /// @notice Packs the loose proof components into precompile structs and verifies them.
    /// @dev Calls `verifyAndEmit`, so the precompile logs `TransactionVerified` — an on-chain
    /// audit trail of every fact this contract acted on. Reverts inside the precompile on a bad
    /// proof, so the `require` on the return value is belt-and-braces.
    function _verifyProof(
        uint64 chainKey,
        uint64 blockHeight,
        bytes calldata encodedTransaction,
        bytes32 merkleRoot,
        INativeQueryVerifier.MerkleProofEntry[] calldata siblings,
        bytes32 lowerEndpointDigest,
        bytes32[] calldata continuityRoots
    ) internal returns (bool verified) {
        INativeQueryVerifier.MerkleProof memory merkleProof =
            INativeQueryVerifier.MerkleProof({root: merkleRoot, siblings: siblings});

        INativeQueryVerifier.ContinuityProof memory continuityProof =
            INativeQueryVerifier.ContinuityProof({lowerEndpointDigest: lowerEndpointDigest, roots: continuityRoots});

        // Verify inclusion proof
        verified = VERIFIER.verifyAndEmit(chainKey, blockHeight, encodedTransaction, merkleProof, continuityProof);

        return verified;
    }

    /// @notice Derives the replay-protection id for a proof.
    /// @dev The id is `keccak256` over a hand-packed 72-byte buffer: chainKey right-aligned in
    /// word 0, blockHeight as 8 big-endian bytes at offset 32, txIndex right-aligned at offset
    /// 40. This is NOT `abi.encodePacked(chainKey, blockHeight, txIndex)` — the layout must match
    /// upstream exactly or ids computed by other tooling will not agree. `txIndex` comes from the
    /// Merkle path itself, so the id cannot be forged without a valid proof.
    function _computeQueryId(
        uint64 chainKey,
        uint64 blockHeight,
        bytes32 merkleRoot,
        INativeQueryVerifier.MerkleProofEntry[] calldata siblings
    ) internal view returns (bytes32 queryId) {
        INativeQueryVerifier.MerkleProof memory merkle_proof =
            INativeQueryVerifier.MerkleProof({root: merkleRoot, siblings: siblings});

        uint256 txIndex = VERIFIER.calculateTxIndex(merkle_proof);

        assembly {
            let ptr := mload(0x40)
            mstore(ptr, chainKey)
            mstore(add(ptr, 32), shl(192, blockHeight))
            mstore(add(ptr, 40), txIndex)
            queryId := keccak256(ptr, 72)
        }
    }
}
