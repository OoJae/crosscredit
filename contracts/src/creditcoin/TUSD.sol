// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TUSD
/// @author CrossCredit
/// @notice The mock stablecoin borrowers draw from `LendingPool`.
/// @dev A demo asset with owner-controlled supply — deliberately not a real stablecoin, and not
/// pretending to be one. It exists so the lending flow has something to lend; the interesting part
/// of CrossCredit is how *terms* are derived from verified cross-chain history, not the asset.
contract TUSD is ERC20, Ownable {
    constructor() ERC20("CrossCredit Test USD", "tUSD") Ownable(msg.sender) {}

    /// @notice Mints supply, used to fund the pool and demo wallets.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
