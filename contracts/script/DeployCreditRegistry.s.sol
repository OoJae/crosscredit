// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CreditRegistry} from "../src/creditcoin/CreditRegistry.sol";
import {SourceKind} from "../src/creditcoin/SourceKinds.sol";

/// @notice Deploys {CreditRegistry} to Creditcoin CC3 testnet and registers its credit sources.
///
/// @dev `EvmV1Decoder` is an external library — all its functions are `public`, so it links by
/// `delegatecall`. Note that `forge script` cannot actually broadcast to CC3: its simulation
/// panics with `header validation error: prevrandao not set` against the Frontier EVM. Deployment
/// uses `forge create --libraries` instead; this script exists for local simulation and as the
/// executable record of which sources are registered.
///
/// Sources registered here are the trust surface. The *proofs* are trustless — what is curated is
/// only which real-world protocols count as credit history.
contract DeployCreditRegistry is Script {
    /// @dev Creditcoin-internal source chain ids. Not EVM chain ids.
    uint64 internal constant SEPOLIA = 1;
    uint64 internal constant MAINNET = 3;

    /// @dev Aave V3 Pool, Ethereum mainnet. Real counterparty capital.
    address internal constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    /// @dev Sparklend Pool — an Aave V3 fork with identical event signatures, so it costs nothing
    /// to support and doubles the addressable history.
    address internal constant SPARKLEND_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;

    /// @dev ENS registration controllers. All four are allowlisted: only v4 issues today, but
    /// older names were registered through earlier controllers and are still provable.
    address internal constant ENS_CONTROLLER_V4 = 0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547;
    address internal constant ENS_CONTROLLER_V3 = 0x253553366Da8546fC250F225fe3d25d0C782303b;
    address internal constant ENS_CONTROLLER_V2 = 0x283Cc5C26e53D66ed2Ea252D986F094B37E6e895;

    /// @dev Proof of Humanity v2 cross-chain proxy, Ethereum mainnet.
    address internal constant POH_V2 = 0xa478095886659168E8812154fB0DE39F103E74b2;

    function run() external returns (CreditRegistry registry) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address loanBook = vm.envAddress("LOANBOOK_ADDRESS");

        vm.startBroadcast(deployerKey);
        registry = new CreditRegistry();
        registerAll(registry, loanBook);
        vm.stopBroadcast();

        console.log("CreditRegistry :", address(registry));
        console.log("owner          :", vm.addr(deployerKey));
    }

    /// @notice Registers every source. Exposed so deploy scripts and tests configure identically.
    function registerAll(CreditRegistry registry, address loanBook) public {
        registry.registerSource(SEPOLIA, loanBook, SourceKind.LoanBook);

        registry.registerSource(MAINNET, AAVE_V3_POOL, SourceKind.AaveV3);
        registry.registerSource(MAINNET, SPARKLEND_POOL, SourceKind.AaveV3);

        registry.registerSource(MAINNET, ENS_CONTROLLER_V4, SourceKind.EnsRegistrar);
        registry.registerSource(MAINNET, ENS_CONTROLLER_V3, SourceKind.EnsRegistrar);
        registry.registerSource(MAINNET, ENS_CONTROLLER_V2, SourceKind.EnsRegistrar);

        registry.registerSource(MAINNET, POH_V2, SourceKind.ProofOfHumanity);
    }
}
