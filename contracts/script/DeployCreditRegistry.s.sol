// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CreditRegistry} from "../src/creditcoin/CreditRegistry.sol";

/// @notice Deploys {CreditRegistry} to Creditcoin CC3 testnet.
///
/// @dev `EvmV1Decoder` is an external library — all its functions are `public`, so it links by
/// `delegatecall` rather than being inlined. Forge deploys it automatically ahead of this script's
/// own transactions, using the CREATE2 deterministic deployer (confirmed live on CC3 at
/// `0x4e59b448…`). That makes the library's address deterministic and the deploy idempotent:
/// re-running skips a library that already exists. No `--libraries` flag or `foundry.toml`
/// pinning is required.
///
/// We deliberately do **not** link the `EvmV1Decoder` already deployed on CC3 at
/// `0x731c345d…`. It is 9,598 bytes from solc 0.8.23 against our 13,261 from 0.8.30 — a different
/// build of unverified provenance. Selectors match, but a library executes by `delegatecall` in
/// *our* storage context, and our test suite validates our build, not that one.
///
/// Run:
/// `forge script contracts/script/DeployCreditRegistry.s.sol --rpc-url $CC3_RPC_URL --broadcast`
contract DeployCreditRegistry is Script {
    function run() external returns (CreditRegistry registry) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // Sourced from docs/evidence/supported-chains.json rather than hardcoded: the same
        // chainKey denotes a different chain on mainnet, so it must travel with the environment.
        uint64 sourceChainKey = uint64(vm.envUint("SOURCE_CHAIN_KEY"));
        address loanBook = vm.envAddress("LOANBOOK_ADDRESS");

        vm.startBroadcast(deployerKey);
        registry = new CreditRegistry(sourceChainKey, loanBook);
        vm.stopBroadcast();

        console.log("CreditRegistry :", address(registry));
        console.log("sourceChainKey :", sourceChainKey);
        console.log("LoanBook       :", loanBook);
        console.log("owner          :", vm.addr(deployerKey));
    }
}
