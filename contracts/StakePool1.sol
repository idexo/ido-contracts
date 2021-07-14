// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./StakeToken.sol";
import "./interfaces/IStakePool.sol";

/**
 * @dev StakePool with multiple reward tokens
 */

contract StakePool1 is StakeToken, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public MONTH = 31 days;
    uint256 public QUARTER = MONTH.mul(3);
    uint256 public YEAR = 365 days;
    uint256 public decimals = 18;

    uint256 private constant _monthlyDistributionRatio = 25;
    uint256 private constant _quarterlyDistributionRatio = 50;
    uint256 private constant _yearlyDistributionRatio = 25;
    uint256 private _minimumStakeAmount = 2500 * 10 ** decimals;

    // Address of deposit token.
    IERC20 public depositToken;
    // Address of reward token.
    IERC20[] public rewardTokens;
    // Timestamp when stake pool was deployed to mainnet.
    uint256 public deployedAt;

    struct RevenueShareDeposit {
        address operator;
        address rewardTokenAddress;
        uint256 amount;
        uint256 depositedAt;
    }

    struct RevenueShareDistribute {
        uint256 totalAmount;
        address[] rewardTokens;
        uint256[] rewardAmounts;
        uint256 distributedAt;
    }

    RevenueShareDeposit[] private _deposits;
    RevenueShareDistribute[] private _monthlyDistributes;
    RevenueShareDistribute[] private _quarterlyDistributes;
    RevenueShareDistribute[] private _yearlyDistributes;
    // stake id => stake claim share.
    mapping(uint256 => uint256) private _stakeClaimShares;
    // account => reward token address => reward amount that staker can withdraw.
    mapping(address => mapping(address => uint256)) private _unlockedRevenueShares;

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
        IERC20[] memory rewardTokens_
    )
        StakeToken(stakeTokenName_, stakeTokenSymbol_)
    {
        depositToken = depositToken_;
        require(rewardTokens_.length > 0, "StakePool1#constructor: REWARD_TOKEN_LENGTH_INVALID");
        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            rewardTokens[i] = rewardTokens_[i];
        }
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
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "StakePool1#onlyAdmin: CALLER_NO_ADMIN_ROLE");
        _;
    }

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "StakePool1#onlyOperator: CALLER_NO_OPERATOR_ROLE");
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
        onlyAdmin
    {
        require(!hasRole(OPERATOR_ROLE, account), "StakePool1#addOperator: ALREADY_OERATOR_ROLE");
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
        onlyAdmin
    {
        require(hasRole(OPERATOR_ROLE, account), "StakePool1#removeOperator: NO_OPERATOR_ROLE");
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
    {
        require(amount >= _minimumStakeAmount, "StakePool1#deposit: UNDER_MINIMUM_STAKE_AMOUNT");
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
    {
        require(amount >= _minimumStakeAmount, "StakePool1#withdraw: UNDER_MINIMUM_STAKE_AMOUNT");
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
        require(depositToken.transferFrom(account, address(this), amount), "StakePool1#_deposit: TRANSFER_FAILED");
        uint256 stakeId = mint(account, amount, block.timestamp);

        emit Deposited(account, stakeId, amount);
    }

    /**
     * @dev If amount is less than amount of the stake, cut off amount.

     * If amount is equal to amount of the stake, burn the stake.

     * @param account address whose stake is being withdrawn.
     * @param stakeId id of stake that is being withdrawn.
     * @param amount withdraw amount.
     */
    function _withdrawStake(
        address account,
        uint256 stakeId,
        uint256 amount
    )
        internal
        nonReentrant
    {
        require(_stakes[stakeId].amount != 0, "StakePool1#_withdraw: STAKE_ID_NOT_FOUND");
        Stake storage stake = _stakes[stakeId];
        require(amount <= stake.amount, "StakePool1#_withdraw: INSUFFICIENT_FUNDS");
        require(depositToken.transfer(account, amount), "StakePool1#_withdraw: TRANSFER_FAILED");
        if (amount == stake.amount) {
            burn(stakeId);
        } else {
            stake.amount = stake.amount.sub(amount);
        }

        emit StakeWithdrawn(account, stakeId, amount);
    }

    /********************************|
    |          Revenue Share         |
    |_______________________________*/

    /**
     * @dev Return unlocked revenue share amount.
     */
    function getUnlockedRevenueShare(
        address rewardTokenAddress
    )
        public
        view
        returns (uint256)
    {
        require(isTokenHolder(_msgSender()), "StakePool1#getUnlockedRevenueShare: CALLER_NO_TOKEN_OWNER");
        return _unlockedRevenueShares[_msgSender()][rewardTokenAddress];
    }

    /**
     * @dev Withdraw unlocked revenue share.
     *
     * @param amount withdraw amount
     */
    function withdrawRevenueShare(
        address rewardTokenAddress,
        uint256 amount
    )
        external
    {
        require(isTokenHolder(_msgSender()), "StakePool1#getUnlockedRevenueShare: CALLER_NO_TOKEN_OWNER");
        require(_unlockedRevenueShares[_msgSender()][rewardTokenAddress] >= amount, "StakePool1#getUnlockedRevenueShare: INSUFFICIENT_FUNDS");
        IERC20(rewardTokenAddress).transfer(_msgSender(), amount);
        emit RevenueShareWithdrawn(_msgSender(), amount);
    }

    /**
     * @dev Deposit revenue shares to the pool.
     * @param amount deposit amount.
     */
    function depositRevenueShare(
        address rewardTokenAddress,
        uint256 amount
    )
        public
        onlyOperator
    {
        require(amount > 0, "StakePool1#depositRevenueShare: ZERO_AMOUNT");
        _depositRevenueShare(msg.sender, rewardTokenAddress, amount);
    }

    /**
     * @dev Deposit revenue shares to the pool.
     * @param account address who deposits to the pool.
     * @param amount deposit amount.
     */
    function _depositRevenueShare(
        address account,
        address rewardTokenAddress,
        uint256 amount
    )
        internal
    {
        IERC20(rewardTokenAddress).safeTransferFrom(account, address(this), amount);
        _deposits.push(RevenueShareDeposit({
            operator: account,
            rewardTokenAddress: rewardTokenAddress,
            amount: amount,
            depositedAt: block.timestamp
        }));
    }

    /**
     * @dev Select eligible stakes that have been in the pool from fromDate and to toDate, and update their claim shares.

     * `toDate` is the current timestamp.

     * @param fromDate timestamp when update calculation begin.
     */
    function updateStakeClaimShares(
        uint256 fromDate
    )
        public
        onlyOperator
        returns (uint256[] memory, uint256)
    {
        require(fromDate <= block.timestamp, "StakePool1#updateStakeClaimShares: NO_PAST_DATE");
        uint256[] memory eligibleStakes = new uint256[](_tokenIds.current());
        uint256 eligibleStakesCount = 0;
        uint256 totalStakeClaim = 0;

        for (uint256 i = 1; i <= _tokenIds.current(); i++) {
            if (_exists(i)) {
                Stake storage stake = _stakes[i];
                if (stake.depositedAt <= fromDate) {
                    totalStakeClaim = totalStakeClaim.add(stake.amount * stake.multiplier);
                    eligibleStakes[eligibleStakesCount++] = i;
                }
            }
        }

        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            Stake storage stake = _stakes[eligibleStakes[i]];
            _stakeClaimShares[eligibleStakes[i]] = (stake.amount * stake.multiplier * 1000).div(totalStakeClaim);
        }

        return (eligibleStakes, eligibleStakesCount);
    }

    /**
     * @dev Distribute revenue shares to stake holders.

     * Currently this function should be called by operator manually and periodically (once a month).
     * May need handling with crons.
     */
    function distribute()
        public
        onlyOperator
    {
        uint256 lastDistributeDate;
        uint256 totalDistributeAmount;
        address[] memory _rewardTokens;
        uint256[] memory distributedAmounts;

        // Monthly distribution
        if (lastDistributeDate + MONTH <= block.timestamp) {
            if (_monthlyDistributes.length == 0) {
                lastDistributeDate = deployedAt;
            } else {
                lastDistributeDate = _monthlyDistributes[_monthlyDistributes.length - 1].distributedAt;
            }
            (totalDistributeAmount, _rewardTokens, distributedAmounts) = _distributeToUsers(lastDistributeDate, _monthlyDistributionRatio);
            RevenueShareDistribute memory newRevenueShareDistribute;
            newRevenueShareDistribute.totalAmount = totalDistributeAmount;
            newRevenueShareDistribute.distributedAt = block.timestamp;
            for (uint256 i = 0; i < _rewardTokens.length ; i++) {
                if (_rewardTokens[i] != address(0)) {
                    newRevenueShareDistribute.rewardTokens[i] = _rewardTokens[i];
                    newRevenueShareDistribute.rewardAmounts[i] = distributedAmounts[i];
                }
            }
            _monthlyDistributes.push(newRevenueShareDistribute);

            emit MonthlyDistributed(totalDistributeAmount, block.timestamp);
        }
        // Quarterly distribution
        if (lastDistributeDate + QUARTER <= block.timestamp) {
            if (_quarterlyDistributes.length == 0) {
                lastDistributeDate = deployedAt;
            } else {
                lastDistributeDate = _quarterlyDistributes[_quarterlyDistributes.length - 1].distributedAt;
            }
            (totalDistributeAmount, _rewardTokens, distributedAmounts) = _distributeToUsers(lastDistributeDate, _quarterlyDistributionRatio);
            RevenueShareDistribute memory newRevenueShareDistribute;
            newRevenueShareDistribute.totalAmount = totalDistributeAmount;
            newRevenueShareDistribute.distributedAt = block.timestamp;
            for (uint256 i = 0; i < _rewardTokens.length ; i++) {
                if (_rewardTokens[i] != address(0)) {
                    newRevenueShareDistribute.rewardTokens[i] = _rewardTokens[i];
                    newRevenueShareDistribute.rewardAmounts[i] = distributedAmounts[i];
                }
            }
            _quarterlyDistributes.push(newRevenueShareDistribute);

            emit QuarterlyDistributed(totalDistributeAmount, block.timestamp);
        }
        // Yearly distribution
        if (lastDistributeDate + YEAR <= block.timestamp) {
            if (_yearlyDistributes.length == 0) {
                lastDistributeDate = deployedAt;
            } else {
                lastDistributeDate = _yearlyDistributes[_yearlyDistributes.length - 1].distributedAt;
            }
            (totalDistributeAmount, _rewardTokens, distributedAmounts) = _distributeToUsers(lastDistributeDate, _yearlyDistributionRatio);
            RevenueShareDistribute memory newRevenueShareDistribute;
            newRevenueShareDistribute.totalAmount = totalDistributeAmount;
            newRevenueShareDistribute.distributedAt = block.timestamp;
            for (uint256 i = 0; i < _rewardTokens.length ; i++) {
                if (_rewardTokens[i] != address(0)) {
                    newRevenueShareDistribute.rewardTokens[i] = _rewardTokens[i];
                    newRevenueShareDistribute.rewardAmounts[i] = distributedAmounts[i];
                }
            }
            _yearlyDistributes.push(newRevenueShareDistribute);

            emit YearlyDistributed(totalDistributeAmount, block.timestamp);
        }
    }

    /**
     * @dev Calculate sum of revenue share deposits to the pool.

     * `toDate` is the current timestamp.
     * @param fromDate timestamp when sum calculation begin.
     */
    function sumDeposits(
        address rewardTokenAddress,
        uint256 fromDate
    )
        public
        view
        onlyOperator
        returns (uint256)
    {
        uint256 totalDepositAmount = 0;
        for (uint256 i = 0; i < _deposits.length; i++) {
            if (_deposits[i].rewardTokenAddress == rewardTokenAddress && _deposits[i].depositedAt >= fromDate ) {
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
        returns (uint256, address[] memory, uint256[] memory)
    {
        uint256[] memory eligibleStakes;
        uint256 eligibleStakesCount;
        uint256 availableDistributeAmount;
        uint256[] memory amounts = new uint256[](rewardTokens.length);
        address[] memory _rewardTokens = new address[](rewardTokens.length);
        uint256 totalDistributeAmount = 0;
        uint256 idx = 0;

        (eligibleStakes, eligibleStakesCount) = updateStakeClaimShares(lastDistributeDate);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            IERC20 rewardToken = rewardTokens[i];
            availableDistributeAmount = sumDeposits(address(rewardToken), lastDistributeDate).mul(distributionRatio).div(100);
            if (availableDistributeAmount > 0) {
                for (uint256 j = 0; j < eligibleStakesCount; j++) {
                    uint256 stakeId = eligibleStakes[j];
                    uint256 stakeClaimShare = _stakeClaimShares[stakeId];
                    uint256 amountShare = availableDistributeAmount.mul(stakeClaimShare).div(1000);
                    require(amountShare <= rewardToken.balanceOf(address(this)), "StakePool1#_distributeToUsers: INSUFFICIENT FUNDS");
                    _unlockedRevenueShares[ownerOf(stakeId)][address(rewardToken)] = _unlockedRevenueShares[ownerOf(stakeId)][address(rewardToken)].add(amountShare);
                    totalDistributeAmount = totalDistributeAmount.add(amountShare);
                    _rewardTokens[idx++] = address(rewardToken);
                    amounts[idx++] = amountShare;
                }
            }
        }

        return (totalDistributeAmount, _rewardTokens, amounts);
    }
}
