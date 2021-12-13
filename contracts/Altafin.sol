// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./presets/ERC20Preset.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Altafin is Initializable, ERC20Preset {
    function init(
        string calldata name,
        string calldata symbol,
        uint256 initialSupply
    ) public virtual initializer {
        __ERC20_init(name, symbol);
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(BLACKLIST_ROLE, _msgSender());
        _mint(_msgSender(), initialSupply);
    }
}
