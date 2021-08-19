// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./StakeToken.sol";
import "./interfaces/IStakePool.sol";

contract StakePool is IStakePool, StakeToken, AccessControl, ReentrancyGuard {
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

    event MonthlyDistributed(uint256 amount, uint256 distributedAt);
    event QuarterlyDistributed(uint256 amount, uint256 distributedAt);
    event YearlyDistributed(uint256 amount, uint256 distributedAt);

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

     * If amount is less than amount of the stake, cut off amount.
     * If amount is equal to amount of the stake, burn the stake.

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
     * @dev Claim reward.
     *
     * @param amount withdraw amount
     */
    function claimReward(
        uint256 amount
    )
        external
        override
        nonReentrant
    {
        require(isTokenHolder(_msgSender()), "StakePool#claimReward: CALLER_NO_TOKEN_OWNER");
        require(claimableRewards[_msgSender()] >= amount, "StakePool#claimReward: INSUFFICIENT_FUNDS");
        claimableRewards[_msgSender()] -= amount;
        rewardToken.transfer(_msgSender(), amount);
        emit RewardClaimed(_msgSender(), amount);
    }

    /**
     * @dev Distribute reward to stake holders.
     *
     * Currently this function should be called by operator manually and periodically (once a month).
     * May need handling with crons.
     */
    function distribute()
        external
        override
        onlyOperator
    {
        uint256 lastDistributeDate;
        uint256 totalDistributeAmount;

        // Monthly distribution
        if (mDistributes.length == 0) {
            lastDistributeDate = deployedAt;
        } else {
            lastDistributeDate = mDistributes[mDistributes.length - 1].distributedAt;
        }
        if (lastDistributeDate + MONTH <= block.timestamp) {
            totalDistributeAmount = _distributeToUsers(lastDistributeDate, mDistributionRatio);
            mDistributes.push(RewardDistribute({
                amount: totalDistributeAmount,
                distributedAt: block.timestamp
            }));

            emit MonthlyDistributed(totalDistributeAmount, block.timestamp);
        }
        // Quarterly distribution
        if (qDistributes.length == 0) {
            lastDistributeDate = deployedAt;
        } else {
            lastDistributeDate = qDistributes[qDistributes.length - 1].distributedAt;
        }
        if (lastDistributeDate + QUARTER <= block.timestamp) {
            totalDistributeAmount = _distributeToUsers(lastDistributeDate, qDistributionRatio);
            qDistributes.push(RewardDistribute({
                amount: totalDistributeAmount,
                distributedAt: block.timestamp
            }));

            emit QuarterlyDistributed(totalDistributeAmount, block.timestamp);
        }
        // Yearly distribution
        if (yDistributes.length == 0) {
            lastDistributeDate = deployedAt;
        } else {
            lastDistributeDate = yDistributes[yDistributes.length - 1].distributedAt;
        }
        if (lastDistributeDate + YEAR <= block.timestamp) {
            totalDistributeAmount = _distributeToUsers(lastDistributeDate, yDistributionRatio);
            yDistributes.push(RewardDistribute({
                amount: totalDistributeAmount,
                distributedAt: block.timestamp
            }));

            emit YearlyDistributed(totalDistributeAmount, block.timestamp);
        }
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
     * @dev Select eligible stakes that have been in the pool from fromDate and to toDate, and update their claim shares.
     *
     * `toDate` is the current timestamp.
     *
     * @param fromDate timestamp when update calculation begin.
     */
    function _calcStakeClaimShares(
        uint256 fromDate
    )
        private
        view
        returns (uint256[] memory, uint256[] memory, uint256)
    {
        require(fromDate <= block.timestamp, "StakePool#_calcStakeClaimShares: NO_PAST_DATE");
        uint256[] memory eligibleStakes = new uint256[](tokenIds);
        uint256[] memory eligibleStakeClaimShares = new uint256[](tokenIds);
        uint256 eligibleStakesCount = 0;
        uint256 totalStakeClaim = 0;

        for (uint256 i = 1; i <= tokenIds; i++) {
            if (_exists(i)) {
                (uint256 amount, uint256 multiplier, uint256 depositedAt) = getStake(i);
                if (depositedAt <= fromDate) {
                    totalStakeClaim += amount * multiplier;
                    eligibleStakes[eligibleStakesCount++] = i;
                }
            }
        }

        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            (uint256 amount, uint256 multiplier, ) = getStake(eligibleStakes[i]);
            eligibleStakeClaimShares[i] = (amount * multiplier * 1000) / totalStakeClaim;
        }

        return (eligibleStakes, eligibleStakeClaimShares, eligibleStakesCount);
    }

    /**
     * @dev Calculate sum of reward deposits to the pool
     * processed from `fromDate` to current timestamp.
     *
     * @param fromDate timestamp when sum calculation begin.
     */
    function _sumDeposits(
        uint256 fromDate
    )
        private
        view
        onlyOperator
        returns (uint256)
    {
        uint256 totalDepositAmount = 0;
        for (uint256 i = 0; i < rewardDeposits.length; i++) {
            if (rewardDeposits[i].depositedAt >= fromDate ) {
                totalDepositAmount += rewardDeposits[i].amount;
            }
        }

        return totalDepositAmount;
    }

    /**
     * @dev Distribute reward to eligible stake holders according to specific conditions.
     * @param lastDistributeDate timestamp when the last distribution was done.
     * @param distributionRatio monthly, quarterly or yearly distribution ratio.
     */
    function _distributeToUsers(
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
        uint256 totalDistributeAmount = 0;

        (eligibleStakes, eligibleStakeClaimShares, eligibleStakesCount) = _calcStakeClaimShares(lastDistributeDate);
        availableDistributeAmount = _sumDeposits(lastDistributeDate) * distributionRatio / 100;
        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            uint256 stakeId = eligibleStakes[i];
            uint256 amountShare = availableDistributeAmount * eligibleStakeClaimShares[i] / 1000;
            require(amountShare <= rewardToken.balanceOf(address(this)), "StakePool#_distributeToUsers: INSUFFICIENT FUNDS");
            claimableRewards[ownerOf(stakeId)] += amountShare;
            totalDistributeAmount += amountShare;
        }

        return totalDistributeAmount;
    }
}
