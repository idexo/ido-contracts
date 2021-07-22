// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * Able to set name and symbol when deploying.
 */
contract IDO1 is ERC20Permit, ERC20Pausable, ERC20Capped, AccessControl {
    address private _owner;
    address private _newOwner;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant HUNDRED_MILLION = 100 * 1000 * 1000 * 10 ** 18;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(
        string memory name,
        string memory symbol
    )
        ERC20(name, symbol)
        ERC20Permit(name)
        ERC20Capped(HUNDRED_MILLION)
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());

        _owner = _msgSender();
        emit OwnershipTransferred(address(0), _msgSender());
    }

    /****************************|
    |          Ownership         |
    |___________________________*/

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "IDO1#onlyOwner: CALLER_NO_OWNER");
        _;
    }

    /**
     * @dev Return the address of the current owner.
     */
    function owner()
        public
        view
        virtual
        returns (address)
    {
        return _owner;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership()
        external
        onlyOwner
    {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfer the contract ownership.
     * The new owner still needs to accept the transfer.
     * can only be called by the contract owner.
     *
     * @param newOwner new contract owner.
     */
    function transferOwnership(
        address newOwner
    )
        external
        onlyOwner
    {
        require(newOwner != address(0), "IDO1#transferOwnership: INVALID_ADDRESS");
        require(newOwner != owner(), "IDO1#transferOwnership: OWNERSHIP_SELF_TRANSFER");
        _newOwner = newOwner;
    }

    /**
     * @dev The new owner accept an ownership transfer.
     */
    function acceptOwnership()
        external
    {
        require(_msgSender() == _newOwner, "IDO1#acceptOwnership: CALLER_NO_NEW_OWNER");
        emit OwnershipTransferred(owner(), _newOwner);
        _owner = _newOwner;
        _newOwner = address(0);
    }

    /***********************|
    |          Role         |
    |______________________*/

    /**
     * @dev Restricted to members of the admin role.
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "IDO1#onlyAdmin: CALLER_NO_ADMIN_ROLE");
        _;
    }

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "IDO1#onlyOperator: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Restricted to members of the pauser role.
     */
    modifier onlyPauser() {
        require(hasRole(PAUSER_ROLE, _msgSender()), "IDO1#onlyPauser: CALLER_NO_PAUSER_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     * @param account address
     */
    function addOperator(
        address account
    )
        public
        onlyAdmin
    {
        require(!hasRole(OPERATOR_ROLE, account), "IDO1#addOperator: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     * @param account address
     */
    function removeOperator(
        address account
    )
        public
        onlyAdmin
    {
        require(hasRole(OPERATOR_ROLE, account), "IDO1#removeOperator: NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
        if (hasRole(PAUSER_ROLE, account)) {
            revokeRole(PAUSER_ROLE, account);
        }
    }

    /**
     * @dev Check if an account is operator.
     * @param account address
     */
    function checkOperator(
        address account
    )
        public
        view
        returns (bool)
    {
        return hasRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Add an account to the pauser role.
     * @param account address
     */
    function addPauser(
        address account
    )
        public
        onlyAdmin
    {
        require(!hasRole(PAUSER_ROLE, account), "IDO1#addPauser: ALREADY_PAUSER_ROLE");
        if (!hasRole(OPERATOR_ROLE, account)) {
            grantRole(OPERATOR_ROLE, account);
        }
        grantRole(PAUSER_ROLE, account);
    }

    /**
     * @dev Remove an account from the pauser role.
     * @param account address
     */
    function removePauser(
        address account
    )
        public
        onlyAdmin
    {
        require(hasRole(PAUSER_ROLE, account), "IDO1#removePauser: NO_PAUSER_ROLE");
        revokeRole(PAUSER_ROLE, account);
    }

    /**
     * @dev Check if an account is pauser.
     * @param account address
     */
    function checkPauser(
        address account
    ) public view returns (bool) {
        return hasRole(PAUSER_ROLE, account);
    }

    /************************|
    |          Token         |
    |_______________________*/

    /**
     * @dev Mint a new token.
     * @param account address
     * @param amount uint256
     */
    function mint(
        address account,
        uint256 amount
    )
        external
        onlyOperator
    {
        _mint(account, amount);
    }

    /**
     * @dev Burn tokens.
     * @param account address
     * @param amount uint256
     */
    function burn(
        address account,
        uint256 amount
    )
        external
        onlyOperator
    {
        _burn(account, amount);
    }

    function _mint(
        address recipient,
        uint256 amount
    )
        internal
        override(ERC20, ERC20Capped)
    {
        ERC20Capped._mint(recipient, amount);
    }

    /**
     * @dev ERC20Pausable._beforeTokenTransfer(from, to, amount) override.
     * @param from address
     * @param to address
     * @param amount uint256
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    )
        internal
        override(ERC20, ERC20Pausable)
    {
        ERC20Pausable._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev Get chain id.
     */
    function getChainId()
        external
        view
        returns (uint256)
    {
        return block.chainid;
    }

    /******************************|
    |          Pausability         |
    |_____________________________*/

    /**
     * @dev Pause.
     */
    function pause()
        public
        onlyPauser
    {
        super._pause();
    }

    /**
     * @dev Unpause.
     */
    function unpause()
        public
        onlyPauser
    {
        super._unpause();
    }
}
