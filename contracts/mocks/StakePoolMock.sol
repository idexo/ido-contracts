// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../staking/StakeToken.sol";
import "../interfaces/IStakePool.sol";

/**
 * Mock version of StakePool.
 * Distribution intervals are shortened for testing.
 * MONTH -> 1 day.
 * QUARTER -> 3 days.
 * YEAR -> 12 days.
 */

contract StakePoolMock is IStakePool, StakeToken, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    // TODO Reconsider
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

    // IDO token
    IERC20 public ido;
    // USDT token
    IERC20 public usdt;
    // Timestamp when stake pool was deployed.
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
        IERC20 ido_,
        IERC20 usdt_
    )
        StakeToken(stakeTokenName_, stakeTokenSymbol_)
    {
        ido = ido_;
        usdt = usdt_;
        deployedAt = block.timestamp;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
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
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "StakePoolMock: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     */
    function addOperator(address account) public override onlyOwner {
        // Check if `account` already has operator role
        require(!hasRole(OPERATOR_ROLE, account), "StakePoolMock: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     */
    function removeOperator(address account) public override onlyOwner {
        // Check if `account` has operator role
        require(hasRole(OPERATOR_ROLE, account), "StakePoolMock: NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     */
    function checkOperator(address account) public override view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /***************************|
    |          Pausable         |
    |__________________________*/

    /**
     * @dev Pause the pool
     */
    function pause() external onlyOperator {
        super._pause();
    }

    /**
     * @dev Unpause the pool
     */
    function unpause() external onlyOperator {
        super._unpause();
    }

    /************************|
    |          Stake         |
    |_______________________*/

    /**
     * @dev Deposit stake to the pool.
     *
     * - `amount` >= `minStakeAmount`
     */
    function deposit(uint256 amount) external override whenNotPaused {
        require(amount >= minStakeAmount, "StakePoolMock: UNDER_MINIMUM_STAKE_AMOUNT");
        _deposit(_msgSender(), amount);
    }

    /**
     * @dev Withdraw stake from the pool.
     *
     * If `amount` is less than amount of the stake, cut down the stake amount.
     * If `amount` is equal to amount of the stake, burn the stake.
     *
     * - `amount` >= `minStakeAmount`
     * - `stakeId` should be valid
     */
    function withdraw(
        uint256 stakeId,
        uint256 amount
    ) external override whenNotPaused {
        require(amount >= minStakeAmount, "StakePoolMock: UNDER_MINIMUM_STAKE_AMOUNT");
        _withdraw(_msgSender(), stakeId, amount);
    }

    /**
     * @dev Deposit stake to the pool.
     * Mint a new StakeToken.
     * Transfer `amount` of IDO from `account` to the pool.
     * Zero account check for `account` happen in {ERC721}.
     */
    function _deposit(
        address account,
        uint256 amount
    ) private nonReentrant {
        uint256 stakeId = super._mint(account, amount, block.timestamp);
        ido.safeTransferFrom(account, address(this), amount);

        emit Deposited(account, stakeId, amount);
    }

    /**
     * @dev If `amount` is less than amount of the stake, cut down the stake amount.
     * If `amount` is equal to amount of the stake, burn the stake.
     * Transfer `withdrawAmount` of IDO from the pool to `account`.
     *
     * - `amount` >= `minStakeAmount`
     * - `stakeId` should be valid
     * - `account` must be owner of `stakeId`
     */
    function _withdraw(
        address account,
        uint256 stakeId,
        uint256 withdrawAmount
    ) private nonReentrant {
        require(ownerOf(stakeId) == account, "StakePoolMock: NO_STAKE_OWNER");
        super._decreaseStakeAmount(stakeId, withdrawAmount);
        ido.safeTransfer(account, withdrawAmount);

        emit Withdrawn(account, stakeId, withdrawAmount);
    }

    /*************************|
    |          Reward         |
    |________________________*/

    /**
     * @dev Deposit reward to the pool.
     * Operators ony can call.
     *
     * - `amount` must not be zero
     */
    function depositReward(uint256 amount) external override onlyOperator {
        require(amount > 0, "StakePoolMock: ZERO_AMOUNT");
        _depositReward(_msgSender(), amount);
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
    ) public override view returns (uint256) {
        require(fromDate < toDate, "StakePoolMock: INVALID_DATE_RANGE");
        uint256 totalDepositAmount;
        for (uint256 i = 0; i < rewardDeposits.length; i++) {
            if (rewardDeposits[i].depositedAt >= fromDate && rewardDeposits[i].depositedAt < toDate) {
                totalDepositAmount += rewardDeposits[i].amount;
            }
        }

        return totalDepositAmount;
    }

    /**
     * @dev Claim reward from the pool.
     * Decrease `claimableRewards` by `amount`.
     * Transfer `amount` of USDT from the pool to `_msgSender()`.
     *
     * - stake holder must call
     * - `amount` must be less than claimable reward
     */
    function claimReward(uint256 amount) external override nonReentrant whenNotPaused {
        require(isHolder(_msgSender()), "StakePoolMock: CALLER_NO_STAKE_HOLDER");
        require(claimableRewards[_msgSender()] >= amount, "StakePoolMock: INSUFFICIENT_CLAIMABLE_REWARD");
        require(amount <= usdt.balanceOf(address(this)), "StakePoolMock: INSUFFICIENT_FUNDS");
        claimableRewards[_msgSender()] -= amount;
        usdt.safeTransfer(_msgSender(), amount);
        emit RewardClaimed(_msgSender(), amount);
    }

    /**
     * @dev Distribute reward to stake holders.
     *
     * Must be invoked by operator manually and periodically (once a month, quarter and year).
     */
    function distribute() external override onlyOperator whenNotPaused {
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
            // TODO check again
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
     * @dev Deposit reward to the pool.
     * Transfer `amount` of USDT from `account` to the pool.
     */
    function _depositReward(
        address account,
        uint256 amount
    ) private {
        usdt.safeTransferFrom(account, address(this), amount);
        rewardDeposits.push(RewardDeposit({
            operator: account,
            amount: amount,
            depositedAt: block.timestamp
        }));
        emit RewardDeposited(account, amount);
    }

    /**
     * @dev Select eligible stakes that have been in the pool from `fromDate`, and update their claim shares.
     *
     * - `fromDate` must be past timestamp
     */
    function _calcStakeClaimShares(uint256 fromDate) private view returns (uint256[] memory, uint256[] memory, uint256) {
        require(fromDate <= block.timestamp, "StakePoolMock: NO_PAST_DATE");
        uint256[] memory eligibleStakes = new uint256[](tokenID);
        uint256[] memory eligibleStakeClaimShares = new uint256[](tokenID);
        uint256 eligibleStakesCount;
        uint256 totalStakeClaim;
        Stake memory stake;

        for (uint256 i = 1; i <= tokenID; i++) {
            if (_exists(i)) {
                stake = stakes[i];
                if (stake.amount > 0 && stake.depositedAt <= fromDate) {
                    totalStakeClaim += stake.amount * stake.multiplier;
                    eligibleStakes[eligibleStakesCount++] = i;
                }
            }
        }

        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            stake = stakes[eligibleStakes[i]];
            eligibleStakeClaimShares[i] = (stake.amount * stake.multiplier * sClaimShareDenominator) / totalStakeClaim;
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
    ) private returns (uint256 totalDistributeAmount) {
        uint256[] memory eligibleStakes;
        uint256[] memory eligibleStakeClaimShares;
        uint256 eligibleStakesCount;
        uint256 availableDistributeAmount;

        (eligibleStakes, eligibleStakeClaimShares, eligibleStakesCount) = _calcStakeClaimShares(lastDistributeDate);
        availableDistributeAmount = getRewardDepositSum(lastDistributeDate, block.timestamp) * distributionRatio / 100;
        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            uint256 stakeId = eligibleStakes[i];
            uint256 amountShare = availableDistributeAmount * eligibleStakeClaimShares[i] / sClaimShareDenominator;
            require(amountShare <= usdt.balanceOf(address(this)), "StakePoolMock: INSUFFICIENT_FUNDS");
            claimableRewards[ownerOf(stakeId)] += amountShare;
            totalDistributeAmount += amountShare;
        }
    }

    /**
     * @dev Withdraw funds from the pool
     * Operators only can call
     *
     * - `token_` must not be zero address
     * - `amount` must not be zero
     */
    function sweep(
        address token_,
        address to,
        uint256 amount
    ) public onlyOwner {
        require(token_ != address(0), "StakePoolMock: TOKEN_ADDRESS_INVALID");
        require(amount > 0, "StakePoolMock: AMOUNT_INVALID");
        IERC20 token = IERC20(token_);
        // balance check is being done in {ERC20}
        token.safeTransfer(to, amount);
        emit Swept(_msgSender(), token_, to, amount);
    }
}
