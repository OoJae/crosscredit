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

    /// @dev Reserve assets whose Aave repayments count toward borrowing capacity. Decimals must be
    /// declared because they live in source-chain *state*, which the precompile cannot prove — it
    /// proves transactions. An unregistered reserve grants no capacity.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant PYUSD = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;

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

        registry.registerReserve(USDC, 6);
        registry.registerReserve(USDT, 6);
        registry.registerReserve(PYUSD, 6);
        registry.registerReserve(WBTC, 8);
        registry.registerReserve(DAI, 18);
        registry.registerReserve(WETH, 18);
    }
}
