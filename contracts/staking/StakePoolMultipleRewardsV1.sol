// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./StakeTokenMultipleRewardsV1.sol";
import "../interfaces/IStakePoolMultipleRewardsV1.sol";

contract StakePoolMultipleRewardsV1 is IStakePoolMultipleRewardsV1, StakeTokenMultipleRewardsV1, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Minimum stake amount
    uint256 public constant minStakeAmount = 500 * 1e18;

    // Address of deposit token.
    IERC20 public depositToken;
    // Mapping of reward tokens.
    mapping(address => IERC20) public rewardTokens;
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
    mapping(address => RewardDeposit[]) public rewardDeposits;

    // tokenId => available reward amount that tokenId can claim.
    mapping(address => mapping(uint256 => uint256)) public claimableRewards;

    event Deposited(address indexed account, uint256 indexed stakeId, uint256 amount, uint256 timestamplock);
    event Withdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);
    event ClaimableRewardDeposited(address indexed account, uint256 amount);
    event RewardDeposited(address indexed account, uint256 amount);
    event RewardClaimed(address indexed account, uint256 amount);
    event Swept(address indexed operator, address token, address indexed to, uint256 amount);

    constructor(
        string memory stakeTokenName_,
        string memory stakeTokenSymbol_,
        string memory stakeTokenBASEUri_,
        IERC20 depositToken_,
        address rewardToken_
    ) StakeTokenMultipleRewardsV1(stakeTokenName_, stakeTokenSymbol_, stakeTokenBASEUri_) {
        depositToken = depositToken_;
        rewardTokens[rewardToken_] = IERC20(rewardToken_);
        deployedAt = block.timestamp;
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
    function deposit(uint256 amount, uint256 timestamplock) external override {
        require(amount >= minStakeAmount, "StakePool#deposit: UNDER_MINIMUM_STAKE_AMOUNT");
        _deposit(msg.sender, amount, timestamplock);
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
    function withdraw(uint256 stakeId, uint256 amount) external override {
        require(amount > 0, "StakePool#withdraw: UNDER_MINIMUM_WITHDRAW_AMOUNT");
        require(stakes[stakeId].timestamplock < block.timestamp, "StakePool#withdraw: STAKE_STILL_LOCKED_FOR_WITHDRAWAL");
        _withdraw(msg.sender, stakeId, amount);
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
     * @param rewardTokenAddress reward token address
     */
    function depositReward(address rewardTokenAddress, uint256 amount) external override onlyOperator {
        require(amount > 0, "StakePool#depositReward: ZERO_AMOUNT");
        _depositReward(msg.sender, rewardTokenAddress, amount);
    }

    /**
     * @dev Return reward deposit info by id.
     * @param rewardTokenAddress reward token address
     */
    function getRewardDeposit(address rewardTokenAddress, uint256 id)
        external
        view
        returns (
            address,
            uint256,
            uint256
        )
    {
        return (
            rewardDeposits[rewardTokenAddress][id].operator,
            rewardDeposits[rewardTokenAddress][id].amount,
            rewardDeposits[rewardTokenAddress][id].depositedAt
        );
    }

    /**
     * @dev Return reward deposit info by id.
     * @param rewardTokenAddress reward token address
     */
    function getClaimableReward(address rewardTokenAddress, uint256 tokenId) external view returns (uint256) {
        return (claimableRewards[rewardTokenAddress][tokenId]);
    }

    /**
     * @dev add to claimable reward for a given token id
     * @param rewardTokenAddress reward token address
     */
    function addClaimableReward(
        address rewardTokenAddress,
        uint256 tokenId,
        uint256 amount
    ) external onlyOperator {
        claimableRewards[rewardTokenAddress][tokenId] += amount;
    }

    /**
     * @dev batch add to claimable reward for given token ids
     */
    function addClaimableRewards(
        address rewardTokenAddress,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external onlyOperator {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            claimableRewards[rewardTokenAddress][tokenIds[i]] += amounts[i];
        }
    }

    /**
     * @dev Claim reward.
     *
     * Requirements:
     *
     * - stake token owner must call
     * - `amount` must be less than claimable reward
     * @param rewardTokenAddress reward token address
     * @param tokenId tokenId
     * @param amount claim amount
     */
    function claimReward(
        address rewardTokenAddress,
        uint256 tokenId,
        uint256 amount
    ) external nonReentrant {
        require((ownerOf(tokenId) == msg.sender), "StakePool#claimReward: CALLER_NO_TOKEN_OWNER");
        require(claimableRewards[rewardTokenAddress][tokenId] >= amount, "StakePool#claimReward: INSUFFICIENT_FUNDS");
        claimableRewards[rewardTokenAddress][tokenId] -= amount;
        rewardTokens[rewardTokenAddress].safeTransfer(msg.sender, amount);
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
    ) public onlyOperator {
        IERC20 token = IERC20(token_);
        // balance check is being done in ERC20
        token.transfer(to, amount);
        emit Swept(msg.sender, token_, to, amount);
    }

    /*************************|
    |     Reward Tokens       |
    |________________________*/

    /**
     * @dev Add new reward token.
     * @param rewardToken_ reward token address.
     */
    function addRewardToken(address rewardToken_) public onlyOperator {
        require(rewardToken_ != address(0), "StakePool#_deposit: ZERO_ADDRESS");
        _addRewardToken(rewardToken_);
    }

    /*************************|
    |   Internal Functions     |
    |________________________*/

    /**
     * @dev Deposit stake to the pool.
     * @param account address of recipient.
     * @param amount deposit amount.
     */
    function _deposit(
        address account,
        uint256 amount,
        uint256 timestamplock
    ) internal nonReentrant {
        uint256 depositedAt = block.timestamp;
        uint256 stakeId = _mint(account, amount, depositedAt, timestamplock);
        require(depositToken.transferFrom(account, address(this), amount), "StakePool#_deposit: TRANSFER_FAILED");

        emit Deposited(account, stakeId, amount, timestamplock);
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
    ) internal nonReentrant {
        require(ownerOf(stakeId) == account, "StakePool#_withdraw: NO_STAKE_OWNER");
        _decreaseStakeAmount(stakeId, withdrawAmount);
        require(depositToken.transfer(account, withdrawAmount), "StakePool#_withdraw: TRANSFER_FAILED");

        emit Withdrawn(account, stakeId, withdrawAmount);
    }

    /**
     * @dev Deposit reward to the pool.
     * @param account address who deposits to the pool.
     * @param amount deposit amount.
     */
    function _depositReward(
        address account,
        address rewardTokenAddress,
        uint256 amount
    ) internal {
        rewardTokens[rewardTokenAddress].safeTransferFrom(account, address(this), amount);
        rewardDeposits[rewardTokenAddress].push(RewardDeposit({ operator: account, amount: amount, depositedAt: block.timestamp }));

        emit RewardDeposited(account, amount);
    }

    /**
     * @dev Add new reward token.
     * @param rewardToken_ reward token address.
     */
    function _addRewardToken(address rewardToken_) internal {
        rewardTokens[rewardToken_] = IERC20(rewardToken_);
    }
}
