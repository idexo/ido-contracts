// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IWIDO.sol";

contract WIDO is IWIDO, ERC20Permit, AccessControl {
    // Contract owner address
    address public owner;
    // Proposed new contract owner address
    address public newOwner;
    // Cross-chain transfer relayer contract address
    address public relayer;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RelayerAddressChanged(address indexed relayer);

    constructor() ERC20("Wrapped Idexo Token", "WIDO") ERC20Permit("Wrapped Idexo Token") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());

        owner = _msgSender();
        emit OwnershipTransferred(address(0), _msgSender());
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

    /****************************|
    |          Ownership         |
    |___________________________*/

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner == _msgSender(), "WIDO: CALLER_NO_OWNER");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() external override onlyOwner {
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
    function transferOwnership(address _newOwner) external override onlyOwner {
        require(_newOwner != address(0), "WIDO: INVALID_ADDRESS");
        require(_newOwner != owner, "WIDO: OWNERSHIP_SELF_TRANSFER");
        newOwner = _newOwner;
    }

    /**
     * @dev The new owner accept an ownership transfer.
     */
    function acceptOwnership() external override {
        require(_msgSender() == newOwner, "WIDO: CALLER_NO_NEW_OWNER");
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
        require(hasRole(OPERATOR_ROLE, _msgSender()), "WIDO: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     * @param account address
     */
    function addOperator(address account) public override onlyOwner {
        require(!hasRole(OPERATOR_ROLE, account), "WIDO: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     * @param account address
     */
    function removeOperator(address account) public override onlyOwner {
        require(hasRole(OPERATOR_ROLE, account), "WIDO: NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     * @param account address
     */
    function checkOperator(address account) public override view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
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
