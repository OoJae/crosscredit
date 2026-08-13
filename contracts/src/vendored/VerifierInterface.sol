// SPDX-License-Identifier: MIT
//
// ─── VENDORED, WITH MODIFICATIONS ────────────────────────────────────────────────────────────
// Source:  gluwa/usc-testnet-bridge-examples — contracts/sol/VerifierInterface.sol
// Commit:  4ff9a3bf5d7fa8dbfec34ae9726d3f81405dca7b  (2026-07-29)
// URL:     https://github.com/gluwa/usc-testnet-bridge-examples/blob/4ff9a3bf/contracts/sol/VerifierInterface.sol
// License: MIT (upstream LICENSE)
//
// Why vendored rather than imported: the interface published in `@gluwa/usc-contracts@0.1.2`
// (contracts/write-ability/INativeQueryVerifier.sol) is, by its own NatSpec, a "lean vendored
// copy" exposing only the single-query view `verify`. It omits `verifyAndEmit`, the batch
// overloads and `calculateTxIndex`, all of which CrossCredit needs.
//
// MODIFICATIONS vs upstream:
//   1. Added the single-query view `verify(...)`.
//   2. Added the batch overloads `verifyAndEmit(...)` and `verify(...)` (arrays + one shared
//      ContinuityProof), which power CrossCredit's "import my whole history in one tx" path.
//   3. Added the `TransactionVerified` event.
//   4. Added NatSpec throughout.
// Signatures 1–3 are transcribed from the canonical precompile ABI shipped with the SDK at
// `@gluwa/usc-sdk@0.18.0/dist/block-prover/block_prover.json`. Struct layouts are byte-identical
// to upstream — do not reorder fields.
// ─────────────────────────────────────────────────────────────────────────────────────────────
pragma solidity ^0.8.23;

/// @title INativeQueryVerifier
/// @notice Interface to Creditcoin's BlockProver precompile — the Attestcoin Protocol's native
/// verifier. It proves that a transaction was included in a block of a supported source chain
/// (Merkle proof) and that the block genuinely belongs to that chain (continuity proof).
/// @dev Lives at `0x0000000000000000000000000000000000000FD2` (4050). The docs now call this the
/// "Block Prover Precompile"; the Solidity identifier is still `INativeQueryVerifier`.
///
/// IMPORTANT: the precompile verifies *inclusion and continuity only*. It deliberately does NOT
/// check whether the transaction succeeded. Consumers MUST decode the receipt and require
/// `receiptStatus == 1` themselves, or a reverted source transaction will be treated as fact.
interface INativeQueryVerifier {
    /// @notice One sibling hash on the Merkle path from the transaction leaf to the root.
    /// @param hash The sibling node's hash.
    /// @param isLeft True when the sibling sits on the left at this level.
    struct MerkleProofEntry {
        bytes32 hash;
        bool isLeft;
    }

    /// @notice Proof that a transaction is included in a source-chain block.
    /// @param root The block's transaction Merkle root.
    /// @param siblings The Merkle path, leaf-adjacent first.
    struct MerkleProof {
        bytes32 root;
        MerkleProofEntry[] siblings;
    }

    /// @notice Proof linking a source block back to an on-chain attestation.
    /// @param lowerEndpointDigest Digest of the attested block anchoring the chain.
    /// @param roots The chain of block roots from that anchor up to the proven block.
    struct ContinuityProof {
        bytes32 lowerEndpointDigest;
        bytes32[] roots;
    }

    /// @notice Emitted by the precompile on a successful `verifyAndEmit` call.
    event TransactionVerified(uint64 chainKey, uint64 height, uint64 transactionIndex);

    /// @notice Verifies one transaction and emits `TransactionVerified`.
    /// @dev Reverts on failure; returns true on success. A `false` return is unreachable, so do
    /// not branch on it — treat a non-reverting call as proof.
    /// @param chainKey Creditcoin-internal source-chain id (NOT the EVM chainId).
    /// @param height Source-chain block number containing the transaction.
    /// @param encodedTransaction The Attestcoin-encoded transaction + receipt payload.
    /// @return True on success.
    function verifyAndEmit(
        uint64 chainKey,
        uint64 height,
        bytes calldata encodedTransaction,
        MerkleProof calldata merkleProof,
        ContinuityProof calldata continuityProof
    ) external returns (bool);

    /// @notice Read-only variant of {verifyAndEmit}; emits nothing.
    /// @dev Reverts on failure. Being a view call it costs no oracle fee, which makes it the
    /// cheap way to replay a captured proof in a fork test.
    /// @return True on success.
    function verify(
        uint64 chainKey,
        uint64 height,
        bytes calldata encodedTransaction,
        MerkleProof calldata merkleProof,
        ContinuityProof calldata continuityProof
    ) external view returns (bool);

    /// @notice Verifies up to ten transactions that share a single continuity proof.
    /// @dev Two limits apply and both are enforced by the precompile: at most `MAX_BATCH_SIZE`
    /// (10) proofs, and every `heights` entry must fall inside a `MAX_BATCH_RANGE` of 1000
    /// blocks. Sharing one continuity proof is what makes the batch cheaper than N single calls.
    /// @param heights One source-block number per transaction, index-aligned with the other arrays.
    /// @param continuityProof The single continuity proof shared by every entry.
    /// @return True on success.
    function verifyAndEmit(
        uint64 chainKey,
        uint64[] calldata heights,
        bytes[] calldata encodedTransactions,
        MerkleProof[] calldata merkleProofs,
        ContinuityProof calldata continuityProof
    ) external returns (bool);

    /// @notice Read-only variant of the batch {verifyAndEmit}; emits nothing.
    /// @return True on success.
    function verify(
        uint64 chainKey,
        uint64[] calldata heights,
        bytes[] calldata encodedTransactions,
        MerkleProof[] calldata merkleProofs,
        ContinuityProof calldata continuityProof
    ) external view returns (bool);

    /// @notice Derives a transaction's index within its block from its Merkle proof.
    /// @dev The index is implied by the left/right turns in the proof path, so it needs no
    /// separate attestation. Used to build a collision-free query id for replay protection.
    function calculateTxIndex(MerkleProof calldata merkle_proof) external view returns (uint64);
}

/// @notice Helper for reaching the BlockProver precompile at its fixed address.
library NativeQueryVerifierLib {
    /// @dev The precompile's address is fixed by the Creditcoin runtime, not deployed.
    address constant PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000FD2;

    function getVerifier() internal pure returns (INativeQueryVerifier) {
        return INativeQueryVerifier(PRECOMPILE_ADDRESS);
    }
}
