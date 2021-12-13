// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// AltaHelix is the coolest club in town. You come in with some AFN, and leave with more! The longer you stay, the more AFN you get.
//
// This contract handles swapping to and from xAFN, AltaFin's staking token.
contract AltaHelix is ERC20("AltaHelix", "xAFN"){

    IERC20 public AFN;

    // Define the AFN token contract
    constructor(IERC20 _AFN) {
        AFN = _AFN;
    }

    // Enter the helix. Pay some AFN. Earn some shares.s
    // Locks AFN and mints xAFN
    function enter(uint256 _amount) public {
        // Gets the amount of AFN locked in the contract
        uint256 totalAFN = AFN.balanceOf(address(this));
        // Gets the amount of xAFN in existence
        uint256 totalShares = totalSupply();
        // If no xAFN exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalAFN == 0) {
            _mint(msg.sender, _amount);
        } 
        // Calculate and mint the amount of xAFN the AFN is worth. The ratio will change overtime, as xAFN is burned/minted and AFN deposited + gained from fees / withdrawn.
        else {
            uint256 what = _amount * totalShares / totalAFN;
            _mint(msg.sender, what);
        }
        // Lock the AFN in the contract
        AFN.transferFrom(msg.sender, address(this), _amount);
    }

    // Leave the helix. Claim back your AFN.
    // Unlocks the staked + gained AFN and burns xAFN
    function leave(uint256 _share) public {
        // Gets the amount of xAFN in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of AFN the xAFN is worth
        uint256 what = _share * AFN.balanceOf(address(this)) / totalShares;
        _burn(msg.sender, _share);
        AFN.transfer(msg.sender, what);
    }

}