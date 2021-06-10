// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IDO.sol";
import "./StakeToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StakePool is StakeToken, AccessControl, ReentrancyGuard {
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

    // Address of the IDO Token Contract.
    IDO public ido;
    // Address of the reward ERC20 Token Contract.
    IERC20 public erc20;
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

    RevenueShareDeposit[] public deposits;
    RevenueShareDistribute[] public monthlyDistributes;
    RevenueShareDistribute[] public quarterlyDistributes;
    RevenueShareDistribute[] public yearlyDistributes;
    // stake id => stake claim share.
    mapping(uint256 => uint256) public stakeClaimShares;

    event Deposited(address indexed account, uint256 indexed stakeId, uint256 amount);
    event Withdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);

    event MonthlyDistributed(uint256 amount, uint256 distributedAt);
    event QuarterlyDistributed(uint256 amount, uint256 distributedAt);
    event YearlyDistributed(uint256 amount, uint256 distributedAt);

    constructor(
        string memory stakeTokenName_,
        string memory stakeTokenSymbol_,
        IDO ido_,
        IERC20 erc20_
    )
        StakeToken(stakeTokenName_, stakeTokenSymbol_)
    {
        ido = ido_;
        erc20 = erc20_;
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
        override(ERC721, AccessControl)
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
        require(amount >= _minimumStakeAmount, "StakePool#deposit: UNDER_MINIMUN_STAKE_AMOUNT");
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
        public
    {
        require(amount >= _minimumStakeAmount, "StakePool#withdraw: UNDER_MINIMUN_STAKE_AMOUNT");
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
        internal
        nonReentrant
    {
        require(ido.transferFrom(account, address(this), amount), "StakePool#_deposit: TRANSFER_FAILED");
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
    function _withdraw(
        address account,
        uint256 stakeId,
        uint256 amount
    )
        internal
        nonReentrant
    {
        require(stakes[stakeId].amount != 0, "StakePool#_withdraw: STAKE_ID_NOT_FOUND");
        Stake storage stake = stakes[stakeId];
        require(amount <= stake.amount, "StakePool#_withdraw: INSUFFICIENT_FUNDS");
        require(ido.transfer(account, amount), "StakePool#_withdraw: TRANSFER_FAILED");
        if (amount == stake.amount) {
            burn(stakeId);
        } else {
            stake.amount = stake.amount.sub(amount);
        }

        emit Withdrawn(account, stakeId, amount);
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
        onlyOperator
    {
        require(amount > 0, "StakePool#depositRevenueShare: ZERO_AMOUNT");
        _depositRevenueShare(msg.sender, amount);
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
        erc20.safeTransferFrom(account, address(this), amount);
        deposits.push(RevenueShareDeposit({
            operator: account,
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
        require(fromDate <= block.timestamp, "StakePool#updateStakeClaimShares: NO_PAST_DATE");
        uint256[] memory eligibleStakes = new uint256[](_tokenIds.current());
        uint256 eligibleStakesCount = 0;
        uint256 totalStakeClaim = 0;

        for (uint256 i = 1; i <= _tokenIds.current(); i++) {
            if (_exists(i)) {
                Stake storage stake = stakes[i];
                if (stake.depositedAt <= fromDate) {
                    totalStakeClaim = totalStakeClaim.add(stake.amount * stake.multiplier);
                    eligibleStakes[eligibleStakesCount++] = i;
                }
            }
        }

        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            Stake storage stake = stakes[eligibleStakes[i]];
            stakeClaimShares[eligibleStakes[i]] = (stake.amount * stake.multiplier * 1000).div(totalStakeClaim);
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

        // Monthly distribution
        if (lastDistributeDate + MONTH <= block.timestamp) {
            if (monthlyDistributes.length == 0) {
                lastDistributeDate = deployedAt;
            } else {
                lastDistributeDate = monthlyDistributes[monthlyDistributes.length - 1].distributedAt;
            }
            totalDistributeAmount = _distributeToUsers(lastDistributeDate, _monthlyDistributionRatio);
            monthlyDistributes.push(RevenueShareDistribute({
                amount: totalDistributeAmount,
                distributedAt: block.timestamp
            }));

            emit MonthlyDistributed(totalDistributeAmount, block.timestamp);
        }
        // Quarterly distribution
        if (lastDistributeDate + QUARTER <= block.timestamp) {
            if (quarterlyDistributes.length == 0) {
                lastDistributeDate = deployedAt;
            } else {
                lastDistributeDate = quarterlyDistributes[quarterlyDistributes.length - 1].distributedAt;
            }
            totalDistributeAmount = _distributeToUsers(lastDistributeDate, _quarterlyDistributionRatio);
            quarterlyDistributes.push(RevenueShareDistribute({
                amount: totalDistributeAmount,
                distributedAt: block.timestamp
            }));

            emit QuarterlyDistributed(totalDistributeAmount, block.timestamp);
        }
        // Yearly distribution
        if (lastDistributeDate + YEAR <= block.timestamp) {
            if (yearlyDistributes.length == 0) {
                lastDistributeDate = deployedAt;
            } else {
                lastDistributeDate = yearlyDistributes[yearlyDistributes.length - 1].distributedAt;
            }
            totalDistributeAmount = _distributeToUsers(lastDistributeDate, _yearlyDistributionRatio);
            yearlyDistributes.push(RevenueShareDistribute({
                amount: totalDistributeAmount,
                distributedAt: block.timestamp
            }));

            emit YearlyDistributed(totalDistributeAmount, block.timestamp);
        }
    }

    /**
     * @dev Calculate sum of revenue share deposits to the pool.

     * `toDate` is the current timestamp.
     * @param fromDate timestamp when sum calculation begin.
     */
    function sumDeposits(
        uint256 fromDate
    )
        public
        view
        onlyOperator
        returns (uint256)
    {
        uint256 totalDepositAmount = 0;
        for (uint256 i = 0; i < deposits.length; i++) {
            if (deposits[i].depositedAt >= fromDate ) {
                totalDepositAmount = totalDepositAmount.add(deposits[i].amount);
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

        (eligibleStakes, eligibleStakesCount) = updateStakeClaimShares(lastDistributeDate);
        availableDistributeAmount = sumDeposits(lastDistributeDate).mul(distributionRatio).div(100);
        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            uint256 stakeId = eligibleStakes[i];
            uint256 stakeClaimShare = stakeClaimShares[stakeId];
            uint256 amountShare = availableDistributeAmount.mul(stakeClaimShare).div(1000);
            require(amountShare <= erc20.balanceOf(address(this)), "StakePool#_distributeToUsers: INSUFFICIENT FUNDS");
            erc20.safeTransfer(ownerOf(stakeId), amountShare);
            totalDistributeAmount = totalDistributeAmount.add(amountShare);
        }

        return totalDistributeAmount;
    }
}
