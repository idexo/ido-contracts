// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../interfaces/ICRED.sol";

contract CRED is ICRED, ERC20Permit, Ownable2Step {
    address public relayer;
    uint256 public constant cap = 10000 * 1000 * 1000 * 1 ether;

    event RelayerAddressChanged(address indexed relayer);

    constructor() ERC20("Idexonaut Cred", "CRED") ERC20Permit("Idexonaut Cred") {
    }

    /**************************|
    |          Setters         |
    |_________________________*/

    /**
     * @dev Set relayer address
     * Only owner can call
     */
    function setRelayer(address newRelayer) external override onlyOwner {
        require(newRelayer != address(0), "WIDO: NEW_RELAYER_ADDRESS_INVALID");
        relayer = newRelayer;

        emit RelayerAddressChanged(newRelayer);
    }

    /************************|
    |          Token         |
    |_______________________*/

    /**
     * @dev Mint new WIDO
     * Only relayer can call
     */
    function mint(
        address account,
        uint256 amount
    ) external override {
        require(_msgSender() == relayer, "WIDO: CALLER_NO_RELAYER");
        require(totalSupply() + amount <= cap, "WIDO: AMOUNT_EXCEEDS_CAP");
        _mint(account, amount);
    }

    /**
     * @dev Burn WIDO
     * Only relayer can call
     */
    function burn(
        address account,
        uint256 amount
    ) external override {
        require(_msgSender() == relayer, "WIDO: CALLER_NO_RELAYER");
        _burn(account, amount);
    }

    /**
     * @dev Get chain id.
     */
    function getChainId() public override view returns (uint256) {
        uint256 id;
        assembly { id := chainid() }
        return id;
    }
}
