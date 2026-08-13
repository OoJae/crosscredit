// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LoanBook} from "../src/sepolia/LoanBook.sol";

/// @notice Deploys {LoanBook} to Ethereum Sepolia — the source chain whose transactions
/// CrossCredit proves to Creditcoin.
/// @dev Run with:
/// `forge script contracts/script/DeployLoanBook.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify`
///
/// Logs the topic0 of every event because `CreditRegistry` hardcodes these as constants — copying
/// them from a deploy log the compiler produced is safer than transcribing signatures by hand.
contract DeployLoanBook is Script {
    function run() external returns (LoanBook book) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        book = new LoanBook();
        vm.stopBroadcast();

        console.log("LoanBook deployed:", address(book));
        console.log("Deployer:", vm.addr(deployerKey));
        console.log("");
        console.log("Event topic0 hashes for CreditRegistry:");
        console.logBytes32(keccak256("LoanOpened(uint256,address,uint256,uint64)"));
        console.logBytes32(keccak256("RepaymentMade(uint256,address,uint256,bool,uint64)"));
        console.logBytes32(keccak256("CollateralAdded(address,uint256)"));
    }
}
