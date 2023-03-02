// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../interfaces/IWrappedToken.sol";

contract UncappedWrappedToken is IWrappedToken, ERC20Permit, Ownable2Step {
    address public relayer;

    event RelayerAddressChanged(address indexed relayer);

    constructor(string memory wTokenName, string memory wTokenSymbol) ERC20(wTokenName, wTokenSymbol) ERC20Permit(wTokenName) {}

    /**************************|
    |          Setters         |
    |_________________________*/

    /**
     * @dev Set relayer address
     * Only owner can call
     */
    function setRelayer(address newRelayer) external override onlyOwner {
        require(newRelayer != address(0), "WTOKEN: NEW_RELAYER_ADDRESS_INVALID");
        relayer = newRelayer;

        emit RelayerAddressChanged(newRelayer);
    }

    /************************|
    |          Token         |
    |_______________________*/

    /**
     * @dev Mint new WTOKEN
     * Only relayer can call
     */
    function mint(address account, uint256 amount) external override {
        require(_msgSender() == relayer, "WTOKEN: CALLER_NO_RELAYER");
        _mint(account, amount);
    }

    /**
     * @dev Burn WTOKEN
     * Only relayer can call
     */
    function burn(address account, uint256 amount) external override {
        require(_msgSender() == relayer, "WTOKEN: CALLER_NO_RELAYER");
        _burn(account, amount);
    }

    /**
     * @dev Get chain id.
     */
    function getChainId() public view override returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }
}
