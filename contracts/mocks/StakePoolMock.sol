// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../StakeToken.sol";
import "../interfaces/IStakePool.sol";

contract StakePoolMock is IStakePool, StakeToken, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    // Intervals are shortened. month -> day, quarter -> week, year -> month
    uint256 public constant MONTH = 1 days;
    uint256 public constant QUARTER = 7 days;
    uint256 public constant YEAR = 31 days;

    uint256 private constant _monthlyDistributionRatio = 25;
    uint256 private constant _quarterlyDistributionRatio = 50;
    uint256 private constant _yearlyDistributionRatio = 25;
    uint256 private constant _minimumStakeAmount = 2500 * 10 ** 18;

    // Address of deposit token.
    IERC20 public depositToken;
    // Address of reward token.
    IERC20 public rewardToken;
    // Timestamp when stake pool was deployed to mainnet.
    uint256 public deployedAt;

    struct RevenueShareDeposit {
        address operator;
        uint256 amount;
        uint256 depositedAt;
    }

    struct RevenueShareDistribute {
        uint256 amount;
        uint256 distributedAt;
    }

    RevenueShareDeposit[] private _deposits;
    RevenueShareDistribute[] private _monthlyDistributes;
    RevenueShareDistribute[] private _quarterlyDistributes;
    RevenueShareDistribute[] private _yearlyDistributes;
    // stake id => stake claim share.
    mapping(uint256 => uint256) private _stakeClaimShares;
    // account => reward amount that staker can withdraw.
    mapping(address => uint256) private _unlockedRevenueShares;

    event Deposited(address indexed account, uint256 indexed stakeId, uint256 amount);
    event StakeWithdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);
    event RevenueShareWithdrawn(address indexed account, uint256 amount);

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
     * @param amount deposit amount.
     */
    function deposit(
        uint256 amount
    )
        public
        override
    {
        require(amount >= _minimumStakeAmount, "StakePoolMock#deposit: UNDER_MINIMUM_STAKE_AMOUNT");
        _deposit(msg.sender, amount);
    }

    /**
     * @dev Withdraw from the pool.

     * If amount is less than amount of the stake, cut off amount.
     * If amount is equal to amount of the stake, burn the stake.

     * @param stakeId id of Stake that is being withdrawn.
     * @param amount withdraw amount.
     */
    function withdrawStake(
        uint256 stakeId,
        uint256 amount
    )
        public
        override
    {
        require(amount >= _minimumStakeAmount, "StakePoolMock#withdrawStake: UNDER_MINIMUM_STAKE_AMOUNT");
        _withdrawStake(msg.sender, stakeId, amount);
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
        internal
        nonReentrant
    {
        require(depositToken.transferFrom(account, address(this), amount), "StakePoolMock#_deposit: TRANSFER_FAILED");
        uint256 stakeId = _mint(account, amount, block.timestamp);

        emit Deposited(account, stakeId, amount);
    }

    /**
     * @dev If amount is less than amount of the stake, cut off amount.

     * If amount is equal to amount of the stake, burn the stake.

     * @param account address whose stake is being withdrawn.
     * @param stakeId id of stake that is being withdrawn.
     * @param withdrawAmount withdraw amount.
     */
    function _withdrawStake(
        address account,
        uint256 stakeId,
        uint256 withdrawAmount
    )
        internal
        nonReentrant
    {
        require(ownerOf(stakeId) == account, "StakePoolMock#_withdrawStake: NO_STAKE_OWNER");
        _decreaseStakeAmount(stakeId, withdrawAmount);
        require(depositToken.transfer(account, withdrawAmount), "StakePoolMock#_withdrawStake: TRANSFER_FAILED");

        emit StakeWithdrawn(account, stakeId, withdrawAmount);
    }

    /********************************|
    |          Revenue Share         |
    |_______________________________*/

    /**
     * @dev Deposit revenue shares to the pool.
     * @param amount deposit amount.
     */
    function depositRevenueShare(
        uint256 amount
    )
        public
        override
        onlyOperator
    {
        require(amount > 0, "StakePoolMock#depositRevenueShare: ZERO_AMOUNT");
        _depositRevenueShare(msg.sender, amount);
    }

    /**
     * @dev Return revenue share deposit by id.
     */
    function getRevenueShareDeposit(
        uint256 id
    )
        external
        view
        returns (address, uint256, uint256)
    {
        return (_deposits[id].operator, _deposits[id].amount, _deposits[id].depositedAt);
    }

    /**
     * @dev Return unlocked revenue share amount.
     */
    function getUnlockedRevenueShare()
        external
        override
        view
        returns (uint256)
    {
        require(isTokenHolder(_msgSender()), "StakePoolMock#getUnlockedRevenueShare: CALLER_NO_TOKEN_OWNER");
        return _unlockedRevenueShares[_msgSender()];
    }

    /**
     * @dev Withdraw unlocked revenue share.
     *
     * @param amount withdraw amount
     */
    function withdrawRevenueShare(
        uint256 amount
    )
        external
        override
        nonReentrant
    {
        require(isTokenHolder(_msgSender()), "StakePoolMock#withdrawRevenueShare: CALLER_NO_TOKEN_OWNER");
        require(_unlockedRevenueShares[_msgSender()] >= amount, "StakePoolMock#withdrawRevenueShare: INSUFFICIENT_FUNDS");
        _unlockedRevenueShares[_msgSender()] = _unlockedRevenueShares[_msgSender()].sub(amount);
        rewardToken.transfer(_msgSender(), amount);
        emit RevenueShareWithdrawn(_msgSender(), amount);
    }

    /**
     * @dev Distribute revenue shares to stake holders.
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
        if (lastDistributeDate + MONTH <= block.timestamp) {
            if (_monthlyDistributes.length == 0) {
                lastDistributeDate = deployedAt;
            } else {
                lastDistributeDate = _monthlyDistributes[_monthlyDistributes.length - 1].distributedAt;
            }
            totalDistributeAmount = _distributeToUsers(lastDistributeDate, _monthlyDistributionRatio);
            _monthlyDistributes.push(RevenueShareDistribute({
                amount: totalDistributeAmount,
                distributedAt: block.timestamp
            }));

            emit MonthlyDistributed(totalDistributeAmount, block.timestamp);
        }
        // Quarterly distribution
        if (lastDistributeDate + QUARTER <= block.timestamp) {
            if (_quarterlyDistributes.length == 0) {
                lastDistributeDate = deployedAt;
            } else {
                lastDistributeDate = _quarterlyDistributes[_quarterlyDistributes.length - 1].distributedAt;
            }
            totalDistributeAmount = _distributeToUsers(lastDistributeDate, _quarterlyDistributionRatio);
            _quarterlyDistributes.push(RevenueShareDistribute({
                amount: totalDistributeAmount,
                distributedAt: block.timestamp
            }));

            emit QuarterlyDistributed(totalDistributeAmount, block.timestamp);
        }
        // Yearly distribution
        if (lastDistributeDate + YEAR <= block.timestamp) {
            if (_yearlyDistributes.length == 0) {
                lastDistributeDate = deployedAt;
            } else {
                lastDistributeDate = _yearlyDistributes[_yearlyDistributes.length - 1].distributedAt;
            }
            totalDistributeAmount = _distributeToUsers(lastDistributeDate, _yearlyDistributionRatio);
            _yearlyDistributes.push(RevenueShareDistribute({
                amount: totalDistributeAmount,
                distributedAt: block.timestamp
            }));

            emit YearlyDistributed(totalDistributeAmount, block.timestamp);
        }
    }

    /**
     * @dev Deposit revenue shares to the pool.
     * @param account address who deposits to the pool.
     * @param amount deposit amount.
     */
    function _depositRevenueShare(
        address account,
        uint256 amount
    )
        internal
    {
        rewardToken.safeTransferFrom(account, address(this), amount);
        _deposits.push(RevenueShareDeposit({
            operator: account,
            amount: amount,
            depositedAt: block.timestamp
        }));
    }

    /**
     * @dev Select eligible stakes that have been in the pool from fromDate and to toDate, and update their claim shares.
     *
     * `toDate` is the current timestamp.
     *
     * @param fromDate timestamp when update calculation begin.
     */
    function _updateStakeClaimShares(
        uint256 fromDate
    )
        private
        onlyOperator
        returns (uint256[] memory, uint256)
    {
        require(fromDate <= block.timestamp, "StakePoolMock#updateStakeClaimShares: NO_PAST_DATE");
        uint256[] memory eligibleStakes = new uint256[](_currentTokenId());
        uint256 eligibleStakesCount = 0;
        uint256 totalStakeClaim = 0;

        for (uint256 i = 1; i <= _currentTokenId(); i++) {
            if (_exists(i)) {
                (uint256 amount, uint256 multiplier, uint256 depositedAt) = getStake(i);
                if (depositedAt <= fromDate) {
                    totalStakeClaim = totalStakeClaim.add(amount * multiplier);
                    eligibleStakes[eligibleStakesCount++] = i;
                }
            }
        }

        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            (uint256 amount, uint256 multiplier, ) = getStake(eligibleStakes[i]);
            _stakeClaimShares[eligibleStakes[i]] = (amount * multiplier * 1000).div(totalStakeClaim);
        }

        return (eligibleStakes, eligibleStakesCount);
    }

    /**
     * @dev Calculate sum of revenue share deposits to the pool.
     *
     * `toDate` is the current timestamp.
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
        for (uint256 i = 0; i < _deposits.length; i++) {
            if (_deposits[i].depositedAt >= fromDate ) {
                totalDepositAmount = totalDepositAmount.add(_deposits[i].amount);
            }
        }

        return totalDepositAmount;
    }

    /**
     * @dev Distribute revenue share to eligible stake holders according to specific conditions.
     * @param lastDistributeDate timestamp when the last distribution was done.
     * @param distributionRatio monthly, quarterly or yearly distribution ratio.
     */
    function _distributeToUsers(
        uint256 lastDistributeDate,
        uint256 distributionRatio
    )
        internal
        returns (uint256)
    {
        uint256[] memory eligibleStakes;
        uint256 eligibleStakesCount;
        uint256 availableDistributeAmount;
        uint256 totalDistributeAmount = 0;

        (eligibleStakes, eligibleStakesCount) = _updateStakeClaimShares(lastDistributeDate);
        availableDistributeAmount = _sumDeposits(lastDistributeDate).mul(distributionRatio).div(100);
        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            uint256 stakeId = eligibleStakes[i];
            uint256 stakeClaimShare = _stakeClaimShares[stakeId];
            uint256 amountShare = availableDistributeAmount.mul(stakeClaimShare).div(1000);
            require(amountShare <= rewardToken.balanceOf(address(this)), "StakePoolMock#_distributeToUsers: INSUFFICIENT FUNDS");
            _unlockedRevenueShares[ownerOf(stakeId)] = _unlockedRevenueShares[ownerOf(stakeId)].add(amountShare);
            totalDistributeAmount = totalDistributeAmount.add(amountShare);
        }

        return totalDistributeAmount;
    }
}
