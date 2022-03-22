// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20VotesComp.sol";

/// @custom:security-contact ammon@altafin.co
contract AltaFinance is ERC20, ERC20Permit, ERC20VotesComp {
    address altaTreasury = address(0x087183a411770a645A96cf2e31fA69Ab89e22F5E);

    constructor() ERC20("Alta Finance", "ALTA") ERC20Permit("Alta Finance") {
        _mint(altaTreasury, 10000000000 * 10**decimals());
    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}
