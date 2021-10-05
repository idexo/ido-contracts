// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./StakeToken.sol";
import "../interfaces/IStakePool.sol";

contract StakePoolSimpleCombined is IStakePool, StakeToken, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant MONTH = 31 days;
    uint256 public constant QUARTER = 93 days;
    uint256 public constant YEAR = 365 days;
    // Reward distribution ratio - monthly, quarterly, yearly
    uint256 public constant mDistributionRatio = 25;
    uint256 public constant qDistributionRatio = 50;
    uint256 public constant yDistributionRatio = 25;
    // Minimum stake amount
    uint256 public constant minStakeAmount = 2500 * 1e18;

    uint256 public constant sClaimShareDenominator = 1e18;

    // Address of deposit token.
    IERC20 public depositToken;
    // Address of reward token.
    IERC20 public rewardToken;
    // Timestamp when stake pool was deployed to mainnet.
    uint256 public deployedAt;

    struct ClaimableRewardDeposit {
        address operator;
        uint256 amount;
        uint256 tokenId;
        uint256 depositedAt;
    }

    struct RewardDeposit {
        address operator;
        uint256 amount;
        uint256 depositedAt;
    }

    
    // Reward deposit history
    ClaimableRewardDeposit[] public claimableRewardDeposits;

    // Reward deposit history
    RewardDeposit[] public rewardDeposits;
   

    // tokenId => available reward amount that tokenId can claim.
    mapping(uint256 => uint256) public claimableRewards;

    event Deposited(address indexed account, uint256 indexed stakeId, uint256 amount);
    event Withdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);
    event ClaimableRewardDeposited(address indexed account, uint256 amount);
    event RewardDeposited(address indexed account, uint256 amount);
    event RewardClaimed(address indexed account, uint256 amount);
    event Swept(address indexed operator, address token, address indexed to, uint256 amount);


    constructor(
        string memory stakeTokenName_,
        string memory stakeTokenSymbol_,
        IERC20 depositToken_,
        IERC20 rewardToken_
    )
        StakeToken(stakeTokenName_, stakeTokenSymbol_)
    {
        depositToken = depositToken_;
        rewardToken = rewardToken_;
        deployedAt = block.timestamp;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @dev Override supportInterface.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(IERC165, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /***********************|
    |          Role         |
    |______________________*/

    /**
     * @dev Restricted to members of the admin role.
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "StakePool#onlyAdmin: CALLER_NO_ADMIN_ROLE");
        _;
    }

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "StakePool#onlyOperator: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     * @param account address of recipient.
     */
    function addOperator(
        address account
    )
        public
        override
        onlyAdmin
    {
        // Check if `account` already has operator role
        require(!hasRole(OPERATOR_ROLE, account), "StakePool#addOperator: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     * @param account address.
     */
    function removeOperator(
        address account
    )
        public
        override
        onlyAdmin
    {
        // Check if `account` has operator role
        require(hasRole(OPERATOR_ROLE, account), "StakePool#removeOperator: NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     * @param account address of operator being checked.
     */
    function checkOperator(
        address account
    )
        public
        override
        view
        returns (bool)
    {
        return hasRole(OPERATOR_ROLE, account);
    }

    /************************|
    |          Stake         |
    |_______________________*/

    /**
     * @dev Deposit stake to the pool.
     * Requirements:
     *
     * - `amount` must not be zero
     * @param amount deposit amount.
     */
    function deposit(
        uint256 amount
    )
        external
        override
    {
        require(amount >= minStakeAmount, "StakePool#deposit: UNDER_MINIMUM_STAKE_AMOUNT");
        _deposit(msg.sender, amount);
    }

    /**
     * @dev Withdraw from the pool.
     *
     * If amount is less than amount of the stake, cut down amount.
     * If amount is equal to amount of the stake, burn the stake.
     *
     * Requirements:
     *
     * - `amount` >= `minStakeAmount`
     * @param stakeId id of Stake that is being withdrawn.
     * @param amount withdraw amount.
     */
    function withdraw(
        uint256 stakeId,
        uint256 amount
    )
        external
        override
    {
        require(amount >= minStakeAmount, "StakePool#withdraw: UNDER_MINIMUM_STAKE_AMOUNT");
        _withdraw(msg.sender, stakeId, amount);
    }

    /**
     * @dev Deposit stake to the pool.
     * @param account address of recipient.
     * @param amount deposit amount.
     */
    function _deposit(
        address account,
        uint256 amount
    )
        private
        nonReentrant
    {
        uint256 stakeId = _mint(account, amount, block.timestamp);
        require(depositToken.transferFrom(account, address(this), amount), "StakePool#_deposit: TRANSFER_FAILED");

        emit Deposited(account, stakeId, amount);
    }

    /**
     * @dev If amount is less than amount of the stake, cut off amount.
     * If amount is equal to amount of the stake, burn the stake.
     *
     * Requirements:
     *
     * - `account` must be owner of `stakeId`
     * @param account address whose stake is being withdrawn.
     * @param stakeId id of stake that is being withdrawn.
     * @param withdrawAmount withdraw amount.
     */
    function _withdraw(
        address account,
        uint256 stakeId,
        uint256 withdrawAmount
    )
        private
        nonReentrant
    {
        require(ownerOf(stakeId) == account, "StakePool#_withdraw: NO_STAKE_OWNER");
        _decreaseStakeAmount(stakeId, withdrawAmount);
        require(depositToken.transfer(account, withdrawAmount), "StakePool#_withdraw: TRANSFER_FAILED");

        emit Withdrawn(account, stakeId, withdrawAmount);
    }

    /*************************|
    |          Reward         |
    |________________________*/

    /**
     * @dev Deposit reward to the pool.
     * Requirements:
     *
     * - `amount` must not be zero
     * @param amount deposit amount.
     */
    function depositReward(
        uint256 amount
    )
        external
        override
        onlyOperator
    {
        require(amount > 0, "StakePool#depositReward: ZERO_AMOUNT");
        _depositReward(msg.sender, amount);
    }

    /**
     * @dev Return reward deposit info by id.
     */
    function getRewardDeposit(
        uint256 id
    )
        external
        view
        returns (address, uint256, uint256)
    {
        return (rewardDeposits[id].operator, rewardDeposits[id].amount, rewardDeposits[id].depositedAt);
    }

    /**
     * @dev Return reward deposit info by id.
     */
    function getClaimableReward(
        uint256 tokenId
    )
        external
        view
        returns (uint256)
    {
        return (claimableRewards[tokenId]);
    }

    /**
     * @dev add to claimable reward for a given staker address
     */
    function addClaimableReward(
        uint256 tokenId,
        uint256 amount
    )
        external
        onlyOperator
    {
        claimableRewards[tokenId] += amount;
    }


    /**
     * @dev Claim reward.
     *
     * Requirements:
     *
     * - stake token owner must call
     * - `amount` must be less than claimable reward
     * @param amount claim amount
     */
    function claimReward(
        uint256 tokenId,
        uint256 amount
    )
        external
        nonReentrant
    {
        require((ownerOf(tokenId) == msg.sender), "StakePool#claimReward: CALLER_NO_TOKEN_OWNER");
        require(claimableRewards[tokenId] >= amount, "StakePool#claimReward: INSUFFICIENT_FUNDS");
        claimableRewards[tokenId] -= amount;
        rewardToken.transfer(msg.sender, amount);
        emit RewardClaimed(msg.sender, amount);
    }

    
    /**
     * @dev Sweep funds
     * Accessible by operators
     */
    function sweep(
        address token_,
        address to,
        uint256 amount
    )
        public
        onlyOperator
    {
        IERC20 token = IERC20(token_);
        // balance check is being done in ERC20
        token.transfer(to, amount);
        emit Swept(msg.sender, token_, to, amount);
    }

    /**
     * @dev Deposit reward to the pool.
     * @param account address who deposits to the pool.
     * @param amount deposit amount.
     */
    function _depositReward(
        address account,
        uint256 amount
    )
        private
    {
        rewardToken.safeTransferFrom(account, address(this), amount);
        rewardDeposits.push(RewardDeposit({
            operator: account,
            amount: amount,
            depositedAt: block.timestamp
        }));
        emit RewardDeposited(account, amount);
    }

   
   
}
