// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract IDO is ERC20Permit, ERC20Pausable, ERC20Capped, Ownable, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 constant HUNDRED_MILLION = 100 * 1000 * 1000 * 10 ** 18;

    enum OwnershipStatus {PROPOSAL, PROPOSAL_ACCEPT, PROPOSAL_REJECT, TRANSFER}
    struct OwnershipParam {
        address oldValue;
        address newValue;
        OwnershipStatus status;
        uint256 timestamp;
    }

    // The address for contract owner.
    OwnershipParam private _ownershipParam;

    event OwnershipProposed(address indexed currentOwner, address indexed proposedOwner);
    event OwnershipProposalAccepted(address indexed currentOwner, address indexed proposedOwner);
    event OwnershipProposalRejected(address indexed currentOwner, address indexed proposedOwner);

    constructor(
        string memory name_,
        string memory symbol_
    )
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        ERC20Capped(HUNDRED_MILLION)
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());

        _ownershipParam.newValue = _msgSender();
        _ownershipParam.status = OwnershipStatus.TRANSFER;
        _ownershipParam.timestamp = block.timestamp;
    }

    /***********************|
    |          Role         |
    |______________________*/

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

    /****************************|
    |          Ownership         |
    |___________________________*/

    /**
     * @dev Propose a new ownership for the contract.
     * Called by current owner.
     * @param account address newly proposed owner address
     */
    function proposeNewOwnership(
        address account
    )
        public
        onlyOwner
    {
        require(account != address(0), "IDO: new owner address should not be 0");
        _ownershipParam.newValue = account;
        _ownershipParam.status = OwnershipStatus.PROPOSAL;
        _ownershipParam.timestamp = 0;

        emit OwnershipProposed(owner(), account);
    }

    /**
     * @dev Accept a new ownership.
     * Called by newly proposed owner.
     * @param accepted bool flag that shows if a newly proposed owner accepted.
     */

    function acceptOwnership(
        bool accepted
    )
        public
    {
        require(_ownershipParam.status == OwnershipStatus.PROPOSAL, "IDO: no new ownership proposal");
        require(_ownershipParam.newValue == _msgSender(), "IDO: not proposed owner");
        if (accepted) {
            _ownershipParam.oldValue = owner();
            _ownershipParam.status = OwnershipStatus.PROPOSAL_ACCEPT;
            emit OwnershipProposalAccepted(owner(), _msgSender());
        } else {
            _ownershipParam.newValue = owner();
            _ownershipParam.status = OwnershipStatus.PROPOSAL_REJECT;
            emit OwnershipProposalRejected(owner(), _msgSender());
        }
        _ownershipParam.timestamp = block.timestamp;
    }

    /**
     * @dev Transfer ownership to a new address.
     * @dev Restricted to admin.
     */
    function transferOwnership()
        public
        onlyOwner
    {
        require(_ownershipParam.status == OwnershipStatus.PROPOSAL_ACCEPT, "IDO: no ownership proposal accepted");
        address newOwner = _ownershipParam.newValue;

        revokeRole(DEFAULT_ADMIN_ROLE, owner());
        _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
        if (!hasRole(OPERATOR_ROLE, newOwner)) {
            _setupRole(OPERATOR_ROLE, newOwner);
        }
        if (!hasRole(PAUSER_ROLE, newOwner)) {
            _setupRole(PAUSER_ROLE, newOwner);
        }
        _ownershipParam.status = OwnershipStatus.TRANSFER;
        super.transferOwnership(newOwner);
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
        public
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
        public
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
