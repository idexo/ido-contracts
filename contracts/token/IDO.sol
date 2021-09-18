// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract IDO is ERC20Permit, ERC20Pausable, AccessControl {
    // Contract owner address
    address public owner;
    // Proposed new contract owner address
    address public newOwner;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant cap = 100 * 1000 * 1000 * 1 ether;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() ERC20("Idexo Token", "IDO") ERC20Permit("Idexo Token") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());

        _mint(_msgSender(), cap);
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
        require(owner == _msgSender(), "IDO: CALLER_NO_OWNER");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    /**
     * @dev Transfer the contract ownership.
     * The new owner still needs to accept the transfer.
     * can only be called by the contract owner.
     *
     * @param _newOwner new contract owner.
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "IDO: INVALID_ADDRESS");
        require(_newOwner != owner, "IDO: OWNERSHIP_SELF_TRANSFER");
        newOwner = _newOwner;
    }

    /**
     * @dev The new owner accept an ownership transfer.
     */
    function acceptOwnership() external {
        require(_msgSender() == newOwner, "IDO: CALLER_NO_NEW_OWNER");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }

    /***********************|
    |          Role         |
    |______________________*/

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "IDO: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     * @param account address
     */
    function addOperator(address account) public onlyOwner {
        require(!hasRole(OPERATOR_ROLE, account), "IDO: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     * @param account address
     */
    function removeOperator(address account) public onlyOwner {
        require(hasRole(OPERATOR_ROLE, account), "IDO: NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     * @param account address
     */
    function checkOperator(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
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
    ) internal override(ERC20, ERC20Pausable) {
        if (from == owner) {
            return;
        }
        ERC20Pausable._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev Get chain id.
     */
    function getChainId() public view returns (uint256) {
        uint256 id;
        assembly { id := chainid() }
        return id;
    }

    /******************************|
    |          Pausability         |
    |_____________________________*/

    /**
     * @dev Pause.
     */
    function pause() public onlyOperator {
        super._pause();
    }

    /**
     * @dev Unpause.
     */
    function unpause() public onlyOperator {
        super._unpause();
    }
}
