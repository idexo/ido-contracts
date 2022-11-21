// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../staking/StakeToken.sol";
import "../interfaces/IStakePool.sol";

/**
 * Mock version of StakePool.
 * Distribution intervals are shortened for testing.
 * MONTH -> 1 day.
 * QUARTER -> 3 days.
 * YEAR -> 12 days.
 */

contract StakePoolMock is IStakePool, StakeToken, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant MONTH = 1 days;
    uint256 public constant QUARTER = 3 days;
    uint256 public constant YEAR = 12 days;
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

    struct RewardDeposit {
        address operator;
        uint256 amount;
        uint256 depositedAt;
    }

    struct RewardDistribute {
        uint256 amount;
        uint256 distributedAt;
    }
    // Reward deposit history
    RewardDeposit[] public rewardDeposits;
    // Reward distribution history - monthly, quarterly, yearly
    RewardDistribute[] public mDistributes;
    RewardDistribute[] public qDistributes;
    RewardDistribute[] public yDistributes;

    // account => available reward amount that staker can claim.
    mapping(address => uint256) public claimableRewards;

    event Deposited(address indexed account, uint256 indexed stakeId, uint256 amount);
    event Withdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);
    event RewardDeposited(address indexed account, uint256 amount);
    event RewardClaimed(address indexed account, uint256 amount);
    event Swept(address indexed operator, address token, address indexed to, uint256 amount);

    event MonthlyDistributed(uint256 amount, uint256 distributedAt);
    event QuarterlyDistributed(uint256 amount, uint256 distributedAt);
    event YearlyDistributed(uint256 amount, uint256 distributedAt);

    constructor(
        string memory stakeTokenName_,
        string memory stakeTokenSymbol_,
        string memory stakeTokenBASEUri_,
        IERC20 depositToken_,
        IERC20 rewardToken_
    )
        StakeToken(stakeTokenName_, stakeTokenSymbol_, stakeTokenBASEUri_)
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
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "StakePoolMock#onlyAdmin: CALLER_NO_ADMIN_ROLE");
        _;
    }

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "StakePoolMock#onlyOperator: CALLER_NO_OPERATOR_ROLE");
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
        require(!hasRole(OPERATOR_ROLE, account), "StakePoolMock#addOperator: ALREADY_OERATOR_ROLE");
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
        require(hasRole(OPERATOR_ROLE, account), "StakePoolMock#removeOperator: NO_OPERATOR_ROLE");
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
        require(amount >= minStakeAmount, "StakePoolMock#deposit: UNDER_MINIMUM_STAKE_AMOUNT");
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
        require(amount >= minStakeAmount, "StakePoolMock#withdraw: UNDER_MINIMUM_STAKE_AMOUNT");
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
        require(depositToken.transferFrom(account, address(this), amount), "StakePoolMock#_deposit: TRANSFER_FAILED");

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
        require(ownerOf(stakeId) == account, "StakePoolMock#_withdraw: NO_STAKE_OWNER");
        _decreaseStakeAmount(stakeId, withdrawAmount);
        require(depositToken.transfer(account, withdrawAmount), "StakePoolMock#_withdraw: TRANSFER_FAILED");

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
        require(amount > 0, "StakePoolMock#depositReward: ZERO_AMOUNT");
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
     * @dev Return sum of reward deposits to the pool processed between `fromDate` and `toDate`.
     * Requirements:
     *
     * - `fromDate` must be less than `toDate`
     */
    function getRewardDepositSum(
        uint256 fromDate,
        uint256 toDate
    )
        public

        view
        returns (uint256)
    {
        require(fromDate < toDate, "StakePoolMock#getRewardDepositSum: INVALID_DATE_RANGE");
        uint256 totalDepositAmount;
        for (uint256 i = 0; i < rewardDeposits.length; i++) {
            if (rewardDeposits[i].depositedAt >= fromDate && rewardDeposits[i].depositedAt < toDate) {
                totalDepositAmount += rewardDeposits[i].amount;
            }
        }

        return totalDepositAmount;
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
        uint256 amount
    )
        external

        nonReentrant
    {
        require(isHolder(msg.sender), "StakePoolMock#claimReward: CALLER_NO_TOKEN_OWNER");
        require(claimableRewards[msg.sender] >= amount, "StakePoolMock#claimReward: INSUFFICIENT_FUNDS");
        claimableRewards[msg.sender] -= amount;
        rewardToken.transfer(msg.sender, amount);
        emit RewardClaimed(msg.sender, amount);
    }

    /**
     * @dev Distribute reward to stake holders.
     *
     * Must be invoked by operator manually and periodically (once a month, quarter and year).
     */
    function distribute()
        external

        onlyOperator
    {
        uint256 lastDistributeDate;
        uint256 totalDistributeAmount;
        uint256 currentDate = block.timestamp;

        // Monthly distribution
        if (mDistributes.length == 0) {
            lastDistributeDate = deployedAt;
        } else {
            lastDistributeDate = mDistributes[mDistributes.length - 1].distributedAt;
        }
        if (lastDistributeDate + MONTH <= currentDate) {
            lastDistributeDate = currentDate - MONTH;
            totalDistributeAmount = _distribute(lastDistributeDate, mDistributionRatio);
            mDistributes.push(RewardDistribute({
                amount: totalDistributeAmount,
                distributedAt: currentDate
            }));

            emit MonthlyDistributed(totalDistributeAmount, currentDate);
        }
        // Quarterly distribution
        if (qDistributes.length == 0) {
            lastDistributeDate = deployedAt;
        } else {
            lastDistributeDate = qDistributes[qDistributes.length - 1].distributedAt;
        }
        if (lastDistributeDate + QUARTER <= currentDate) {
            lastDistributeDate = currentDate - QUARTER;
            totalDistributeAmount = _distribute(lastDistributeDate, qDistributionRatio);
            qDistributes.push(RewardDistribute({
                amount: totalDistributeAmount,
                distributedAt: currentDate
            }));

            emit QuarterlyDistributed(totalDistributeAmount, currentDate);
        }
        // Yearly distribution
        if (yDistributes.length == 0) {
            lastDistributeDate = deployedAt;
        } else {
            lastDistributeDate = yDistributes[yDistributes.length - 1].distributedAt;
        }
        if (lastDistributeDate + YEAR <= currentDate) {
            lastDistributeDate = currentDate - YEAR;
            totalDistributeAmount = _distribute(lastDistributeDate, yDistributionRatio);
            yDistributes.push(RewardDistribute({
                amount: totalDistributeAmount,
                distributedAt: currentDate
            }));

            emit YearlyDistributed(totalDistributeAmount, currentDate);
        }
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

    /**
     * @dev Select eligible stakes that have been in the pool from `fromDate`, and update their claim shares.
     * Requirements:
     *
     * - `fromDate` must be past timestamp
     */
    function _calcStakeClaimShares(
        uint256 fromDate
    )
        private
        view
        returns (uint256[] memory, uint256[] memory, uint256)
    {
        require(fromDate <= block.timestamp, "StakePoolMock#_calcStakeClaimShares: NO_PAST_DATE");
        uint256[] memory eligibleStakes = new uint256[](tokenIds);
        uint256[] memory eligibleStakeClaimShares = new uint256[](tokenIds);
        uint256 eligibleStakesCount;
        uint256 totalStakeClaim;

        for (uint256 i = 1; i <= tokenIds; i++) {
            if (_exists(i)) {
                (uint256 amount, uint256 multiplier, uint256 depositedAt) = getStakeInfo(i);
                if (amount > 0 && depositedAt <= fromDate) {
                    totalStakeClaim += amount * multiplier;
                    eligibleStakes[eligibleStakesCount++] = i;
                }
            }
        }

        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            (uint256 amount, uint256 multiplier, ) = getStakeInfo(eligibleStakes[i]);
            eligibleStakeClaimShares[i] = (amount * multiplier * sClaimShareDenominator) / totalStakeClaim;
        }

        return (eligibleStakes, eligibleStakeClaimShares, eligibleStakesCount);
    }

    /**
     * @dev Distribute reward to eligible stake holders according to specific conditions.
     * @param lastDistributeDate timestamp when the last distribution was done.
     * @param distributionRatio monthly, quarterly or yearly distribution ratio.
     */
    function _distribute(
        uint256 lastDistributeDate,
        uint256 distributionRatio
    )
        private
        returns (uint256)
    {
        uint256[] memory eligibleStakes;
        uint256[] memory eligibleStakeClaimShares;
        uint256 eligibleStakesCount;
        uint256 availableDistributeAmount;
        uint256 totalDistributeAmount;

        (eligibleStakes, eligibleStakeClaimShares, eligibleStakesCount) = _calcStakeClaimShares(lastDistributeDate);
        availableDistributeAmount = getRewardDepositSum(lastDistributeDate, block.timestamp) * distributionRatio / 100;
        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            uint256 stakeId = eligibleStakes[i];
            uint256 amountShare = availableDistributeAmount * eligibleStakeClaimShares[i] / sClaimShareDenominator;
            require(amountShare <= rewardToken.balanceOf(address(this)), "StakePoolMock#_distribute: INSUFFICIENT FUNDS");
            claimableRewards[ownerOf(stakeId)] += amountShare;
            totalDistributeAmount += amountShare;
        }

        return totalDistributeAmount;
    }
}
