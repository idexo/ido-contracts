// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IDO.sol";
import "./StakeToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract StakePool is StakeToken, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    using SafeERC20 for IERC20;

    IDO private _ido;
    IERC20 private _rewardToken;
    uint256 private _minimumStakeAmount = 2500;

    event Deposited(address indexed account, uint256 indexed stakeId, uint256 amount);
    event Withdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);
    event EmergencyWithdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);

    uint256 private constant YEAR = 365 days;
    uint256 private constant MONTH = 31 days;

    constructor(
        IDO ido_,
        IERC20 rewardToken_
    )
        public
        StakeToken()
    {
        _ido = ido_;
        _rewardToken = rewardToken_;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    /************************ ROLE MANAGEMENT **********************************/

    /**
     * @dev Restricted to members of the admin role.
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "StakePool: not admin");
        _;
    }

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "StakePool: not operator");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     * @param account address
     */
    function addOperator(address account) public onlyAdmin {
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     * @param account address
     */
    function removeOperator(address account) public onlyAdmin {
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     * @param account address
     */
    function checkOperator(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /************************ ROLE MANAGEMENT **********************************/

    function depositReward(
        uint256 amount
    )
        external
        onlyOperator
    {
        _rewardToken.transfer(address(this), amount);
    }

    function deposit(
        uint256 amount
    )
        public
    {
        require(amount >= _minimumStakeAmount, "StakePool: under minium stake amount");
        require(_ido.transferFrom(msg.sender, address(this), amount), "StakePool: transfer IDO from caller to stake pool failed");
        uint256 stakeId = _mint(msg.sender, amount, block.timestamp);

        emit Deposited(msg.sender, stakeId, amount);
    }

    function withdraw(
        uint256 stakeId,
        uint256 amount
    )
        public
        onlyStaker(msg.sender)
    {
        Stake storage stake = _stakes[msg.sender][stakeId];
        require(stake.amount >= amount, "StakePool: insufficient funds");
        // distribute rewards missing now
        _ido.transferFrom(address(this), msg.sender, amount);
        stake.amount = 0;
    }

    function emergencyWithdraw(
        uint256 stakeId,
        uint256 amount
    )
        public
        onlyStaker(msg.sender)
    {
        Stake storage stake = _stakes[msg.sender][stakeId];
        require(stake.amount >= amount, "StakePool: insufficient funds");
        _ido.transferFrom(address(this), msg.sender, amount);
        stake.amount = 0;
    }
}
