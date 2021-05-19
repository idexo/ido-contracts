// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IDO.sol";
import "./StakeToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract StakePool is StakeToken, AccessControl {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    // todo need update from oracle contract
    uint256 public MONTH = 31 days;
    uint256 public QUARTER = MONTH.mul(3);
    uint256 public YEAR = 365 days;

    uint256 private constant _monthlyDistributionRatio = 25;
    uint256 private constant _quarterlyDistributionRatio = 50;
    uint256 private constant _yearlyDistributionRatio = 25;

    IDO private _ido;
    IERC20 private _rewardToken;
    uint256 private _minimumStakeAmount = 2500;
    uint256 private _deployedAt;
    uint256 private _balanceOfRewardToken;

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
    mapping(uint256 => uint256) private _stakeClaimShares;

    event Deposited(address indexed account, uint256 indexed stakeId, uint256 amount);
    event Withdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);
    event EmergencyWithdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);

    constructor(
        string memory stakeTokenName_,
        string memory stakeTokenSymbol_,
        IDO ido_,
        IERC20 rewardToken_
    )
        StakeToken(stakeTokenName_, stakeTokenSymbol_)
    {
        _ido = ido_;
        _rewardToken = rewardToken_;
        _deployedAt = block.timestamp;

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

    function depositRevenueShare(
        uint256 amount
    )
        external
        onlyOperator
    {
        require(amount >= 0, "StakePool: amount should not be zero");
        require(_rewardToken.transfer(address(this), amount), "StakePool: revenue share deposit failed");
        _deposits.push(RevenueShareDeposit({
            operator: msg.sender,
            amount: amount,
            depositedAt: block.timestamp
        }));
    }

    function updateStakeClaimShares(
        uint256 fromDate
    )
        public
        onlyOperator
        returns (uint256[] memory, uint256)
    {
        require(fromDate < block.timestamp, "StakePool: not past date");
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
            _stakeClaimShares[eligibleStakes[i]] = (stake.amount * stake.multiplier * 100).div(totalStakeClaim);
        }

        return (eligibleStakes, eligibleStakesCount);
    }

    function distribute()
        public
        onlyOperator
    {
        uint256 lastDistributeDate;
        uint256 totalDistributeAmount;

        // Monthly distribution
        if (_monthlyDistributes.length == 0) {
            lastDistributeDate = _deployedAt;
        } else {
            lastDistributeDate = _monthlyDistributes[_monthlyDistributes.length - 1].distributedAt;
        }
        require(lastDistributeDate + MONTH <= block.timestamp, "StakePool: less than a month from last distribution");
        totalDistributeAmount = distributeToUsers(lastDistributeDate, _monthlyDistributionRatio);
        _monthlyDistributes.push(RevenueShareDistribute({
            amount: totalDistributeAmount,
            distributedAt: block.timestamp
        }));
        // Quarterly distribution
        if (_quarterlyDistributes.length == 0) {
            lastDistributeDate = _deployedAt;
        } else {
            lastDistributeDate = _quarterlyDistributes[_quarterlyDistributes.length - 1].distributedAt;
        }
        require(lastDistributeDate + QUARTER <= block.timestamp, "StakePool: less than a quarter from last distribution");
        totalDistributeAmount = distributeToUsers(lastDistributeDate, _quarterlyDistributionRatio);
        _quarterlyDistributes.push(RevenueShareDistribute({
            amount: totalDistributeAmount,
            distributedAt: block.timestamp
        }));
        // Yearly distribution
        if (_yearlyDistributes.length == 0) {
            lastDistributeDate = _deployedAt;
        } else {
            lastDistributeDate = _yearlyDistributes[_yearlyDistributes.length - 1].distributedAt;
        }
        require(lastDistributeDate + YEAR <= block.timestamp, "StakePool: less than a year from last distribution");
        totalDistributeAmount = distributeToUsers(lastDistributeDate, _yearlyDistributionRatio);
        _yearlyDistributes.push(RevenueShareDistribute({
            amount: totalDistributeAmount,
            distributedAt: block.timestamp
        }));
    }

    function distributeToUsers(
        uint256 lastDistributeDate,
        uint256 distributionRatio
    )
        public
        onlyOperator
        returns (uint256)
    {
        uint256[] memory eligibleStakes;
        uint256 eligibleStakesCount;
        uint256 totalDistributeAmount;

        (eligibleStakes, eligibleStakesCount) = updateStakeClaimShares(lastDistributeDate);
        totalDistributeAmount = sumDeposits(lastDistributeDate).mul(distributionRatio).div(100);
        for (uint256 i = 0; i < eligibleStakesCount; i++) {
            uint256 stakeId = eligibleStakes[i];
            Stake storage stake = _stakes[stakeId];
            uint256 stakeClaimShare = _stakeClaimShares[stakeId];
            uint256 amountShare = totalDistributeAmount.mul(stakeClaimShare).div(100);
            require(amountShare <= _rewardToken.balanceOf(address(this)), "StakePool: insufficient funds");
            stake.depositedAt = block.timestamp;
            _rewardToken.transfer(ownerOf(stakeId), amountShare);
        }

        return totalDistributeAmount;
    }

    function sumDeposits(
        uint256 fromDate
    )
        public
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

    function updateBalanceOfRewardToken()
        public
        onlyOperator
    {
        _balanceOfRewardToken = _rewardToken.balanceOf(address(this));
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
    {
        require(amount >= _minimumStakeAmount, "StakePool: under minium stake amount");
        Stake storage stake = _stakes[stakeId];
        require(amount <= stake.amount, "StakePool: insufficient funds");
        if (amount == stake.amount) {
            _burn(stakeId);
        } else {
            stake.amount = stake.amount.sub(amount);
        }
        _ido.transferFrom(address(this), msg.sender, amount);

        emit Withdrawn(msg.sender, stakeId, amount);
    }
}
