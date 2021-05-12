// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract IDO is ERC20Permit, ERC20Pausable, ERC20Capped, Ownable, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 private _totalSupply;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 cap_
    )
        public
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        ERC20Capped(cap_)
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    /**
     * @dev Restricted to members of the admin role.
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "IDO: not admin");
        _;
    }

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "IDO: not operator");
        _;
    }

    /**
     * @dev Restricted to members of the pauser role.
     */
    modifier onlyPauser() {
        require(hasRole(PAUSER_ROLE, _msgSender()), "IDO: not pauser");
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
        require(!hasRole(OPERATOR_ROLE, account), "IDO: already operator");
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
        require(hasRole(OPERATOR_ROLE, account), "IDO: not operator");
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
        require(!hasRole(PAUSER_ROLE, account), "IDO: already pauser");
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
        require(hasRole(PAUSER_ROLE, account), "IDO: not pauser");
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

    /**
     * @dev Transfer ownership to a new address.
     * @dev Restricted to admin.
     * @param newOwner address
     */
    function transferOwnership(
        address newOwner
    )
        public
        override
        onlyAdmin
    {
        renounceRole(DEFAULT_ADMIN_ROLE, owner());
        _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
        if (!hasRole(OPERATOR_ROLE, newOwner)) {
            _setupRole(OPERATOR_ROLE, newOwner);
        }
        if (!hasRole(PAUSER_ROLE, newOwner)) {
            _setupRole(PAUSER_ROLE, newOwner);
        }
        super.transferOwnership(newOwner);
    }

    /**
     * @dev Mint a new token.
     * @param recipient address
     * @param amount uint256
     */
    function mint(
        address recipient,
        uint256 amount
    )
        public
        onlyOperator
    {
        _mint(recipient, amount);
    }

    function _mint(
        address recipient,
        uint256 amount
    )
        internal
        override(ERC20, ERC20Capped)
    {
        super._mint(recipient, amount);
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
        super._beforeTokenTransfer(from, to, amount);
    }

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
}
