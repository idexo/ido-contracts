// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./WIDO.sol";

contract WIDOPausable is WIDO, ERC20Pausable, AccessControl {
    /**
     * @dev `_beforeTokenTransfer` hook override.
     * @param from address
     * @param to address
     * @param amount uint256
     * `Owner` can only transfer when paused
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Pausable) {
        if (from == owner) {
            return;
        }
        ERC20Pausable._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev Pause.
     */
    function pause() public onlyOwner {
        super._pause();
    }

    /**
     * @dev Unpause.
     */
    function unpause() public onlyOwner {
        super._unpause();
    }
}
