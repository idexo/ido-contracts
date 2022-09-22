// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Token is ERC20Capped, AccessControl {
    // Contract owner address
    address public owner;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(
        string memory tokenName_,
        string memory tokenSymbol_,
        uint256 cap_
    ) ERC20(tokenName_, tokenSymbol_) ERC20Capped(cap_ * 1 ether) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());

        owner = _msgSender();
        emit OwnershipTransferred(address(0), _msgSender());
    }

    /****************************|
    |          Ownership         |
    |___________________________*/

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner == _msgSender(), "CALLER_NO_OWNER");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     * `owner` should first call {removeOperator} for himself.
     */
    function renounceOwnership() external onlyOwner {
        owner = address(0);
        emit OwnershipTransferred(owner, address(0));
    }

    /**
     * @dev Transfer the contract ownership.
     * The new owner still needs to accept the transfer.
     * can only be called by the contract owner.
     *
     * @param _newOwner new contract owner.
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "INVALID_ADDRESS");
        require(_newOwner != owner, "OWNERSHIP_SELF_TRANSFER");
        owner = _newOwner;
        emit OwnershipTransferred(owner, _newOwner);
    }

    /***********************|
    |          Role         |
    |______________________*/

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     * @param account address
     */
    function addOperator(address account) public onlyOwner {
        require(!hasRole(OPERATOR_ROLE, account), "ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     * @param account address
     */
    function removeOperator(address account) public onlyOwner {
        require(hasRole(OPERATOR_ROLE, account), "NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     * @param account address
     */
    function checkOperator(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Mint token.
     * @param account address
     * @param amount uint256
     */
    function mint(address account, uint256 amount) public onlyOperator {
        super._mint(account, amount);
    }

    /************************|
    |          Token         |
    |_______________________*/

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
    ) internal override(ERC20) {
        require(from != to, "SELF_TRANSFER");
        super._beforeTokenTransfer(from, to, amount);
    }
}
