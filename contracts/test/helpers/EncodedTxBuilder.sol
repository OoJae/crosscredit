// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";

/// @notice Builds payloads in the Attestcoin `encodedTransaction` format for tests.
/// @dev The format is `abi.encode(uint8 txType, bytes[] chunks)`, where each chunk is itself an
/// independently ABI-encoded blob. For transaction types 0–2 there are three chunks and the
/// receipt is at index 2; types 3–4 use four chunks with the receipt at index 3. Sepolia is
/// post-London, so real proofs are type 2.
///
/// Synthetic payloads let the negative-path tests express things a real prover would never
/// produce — a reverted receipt, a spoofed emitter, an unknown event signature — which is exactly
/// what the registry's validation chain exists to reject. The happy paths are additionally
/// checked against **real** captured proofs in `contracts/test/fixtures/`.
library EncodedTxBuilder {
    /// @notice Wraps logs into a full encoded transaction with the given receipt status.
    /// @param txType Transaction type; 2 mirrors Sepolia.
    /// @param receiptStatus 1 for success, 0 for a reverted source transaction.
    function encode(uint8 txType, uint8 receiptStatus, EvmV1Decoder.LogEntryTuple[] memory logs)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory commonChunk = abi.encode(
            uint64(1), // nonce
            uint64(21000), // gasLimit
            address(0xA11CE), // from
            false, // toIsNull
            address(0xB0B), // to
            uint256(0), // value
            bytes("") // data
        );

        bytes memory typeChunk = abi.encode(
            uint64(11155111), // chainId
            uint128(1 gwei), // maxPriorityFeePerGas
            uint128(2 gwei), // maxFeePerGas
            new EvmV1Decoder.AccessListEntry[](0),
            uint8(0), // yParity
            bytes32(0), // r
            bytes32(0) // s
        );

        bytes memory receiptChunk = abi.encode(receiptStatus, uint64(50000), logs, bytes(hex"00"));

        bytes[] memory chunks = new bytes[](3);
        chunks[0] = commonChunk;
        chunks[1] = typeChunk;
        chunks[2] = receiptChunk;

        return abi.encode(txType, chunks);
    }

    /// @notice Convenience wrapper for a successful type-2 transaction carrying one log.
    function single(EvmV1Decoder.LogEntryTuple memory log) internal pure returns (bytes memory) {
        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = log;
        return encode(2, 1, logs);
    }

    /// @notice `LoanOpened(uint256 indexed loanId, address indexed borrower, uint256 principal, uint64 dueDate)`.
    function loanOpened(address emitter, bytes32 sig, uint256 loanId, address borrower, uint256 principal, uint64 due)
        internal
        pure
        returns (EvmV1Decoder.LogEntryTuple memory log)
    {
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = sig;
        topics[1] = bytes32(loanId);
        topics[2] = bytes32(uint256(uint160(borrower)));
        log = EvmV1Decoder.LogEntryTuple({
            address_: emitter,
            topics: topics,
            data: abi.encode(principal, due)
        });
    }

    /// @notice `RepaymentMade(uint256 indexed loanId, address indexed borrower, uint256 amount, bool onTime, uint64 timestamp)`.
    function repaymentMade(
        address emitter,
        bytes32 sig,
        uint256 loanId,
        address borrower,
        uint256 amount,
        bool onTime
    ) internal pure returns (EvmV1Decoder.LogEntryTuple memory log) {
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = sig;
        topics[1] = bytes32(loanId);
        topics[2] = bytes32(uint256(uint160(borrower)));
        log = EvmV1Decoder.LogEntryTuple({
            address_: emitter,
            topics: topics,
            data: abi.encode(amount, onTime, uint64(1_786_000_000))
        });
    }

    /// @notice `CollateralAdded(address indexed borrower, uint256 amount)`.
    function collateralAdded(address emitter, bytes32 sig, address borrower, uint256 amount)
        internal
        pure
        returns (EvmV1Decoder.LogEntryTuple memory log)
    {
        bytes32[] memory topics = new bytes32[](2);
        topics[0] = sig;
        topics[1] = bytes32(uint256(uint160(borrower)));
        log = EvmV1Decoder.LogEntryTuple({address_: emitter, topics: topics, data: abi.encode(amount)});
    }
}
