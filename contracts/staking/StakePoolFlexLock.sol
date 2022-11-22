// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./StakeTokenFlexLock.sol";

contract StakePoolFlexLock is StakeTokenFlexLock, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Minimum stake amount
    uint256 public minStakeAmount;

    // Address of deposit token.
    IERC20 public depositToken;
    // Mapping of reward tokens.
    mapping(address => IERC20) public rewardTokens;
    // Timestamp when stake pool was deployed to mainnet.
    uint256 public deployedAt;

    struct ClaimableRewardAddition {
        address operator;
        uint256 amount;
        uint256 depositedAt;
        address rewardToken;
    }

    struct RewardDeposit {
        address operator;
        uint256 amount;
        uint256 depositedAt;
    }

    // Reward deposit history
    mapping(address => RewardDeposit[]) public rewardDeposits;

    // Reward claim addition history
    mapping(uint256 => ClaimableRewardAddition[]) public rewardClaims;

    // tokenId => available reward amount that tokenId can claim.
    mapping(address => mapping(uint256 => uint256)) public claimableRewards;

    event Deposited(address indexed account, uint256 indexed stakeId, uint256 amount, uint256 lockedUntil);
    event Withdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);
    event ClaimableRewardAdded(uint256 indexed stakeId, address indexed rewardTokenAddress, uint256 amount);
    event RewardDeposited(address indexed account, address indexed rewardTokenAddress, uint256 amount);
    event RewardClaimed(address indexed account, address indexed rewardTokenAddress, uint256 amount);
    event Swept(address indexed operator, address token, address indexed to, uint256 amount);
    event Relocked(uint256 indexed stakeId, string stakeType, uint256 amount);

    constructor(
        string memory stakeTokenName_,
        string memory stakeTokenSymbol_,
        string memory stakeTokenBASEUri_,
        uint256 minStakeAmount_,
        IERC20 depositToken_,
        address rewardToken_
    ) StakeTokenFlexLock(stakeTokenName_, stakeTokenSymbol_, stakeTokenBASEUri_) {
        minStakeAmount = minStakeAmount_;
        depositToken = depositToken_;
        rewardTokens[rewardToken_] = IERC20(rewardToken_);
        deployedAt = block.timestamp;
    }

    /************************|
    |    Deposit and Lock    |
    |_______________________*/

    /**
     * @dev Set minStakeAmount.
     * Requirements:
     *
     * - `amount` must not be zero
     * @param minStakeAmount_ minStakeAmount
     */

    function setMinStakeAmount(uint256 minStakeAmount_) external onlyOperator {
        require(minStakeAmount_ > 0, "StakePoolFlex: ZERO_AMOUNT");
        minStakeAmount = minStakeAmount_;
    }

    /************************|
    |    Deposit and Lock    |
    |_______________________*/

    /**
     * @dev Deposit stake to the pool.
     * Requirements:
     *
     * - `amount` must not be zero
     * @param amount deposit amount.
     * @param stakeType string valid stakeType.
     * @param compounding bool is compounding.
     */
    function deposit(
        uint256 amount,
        string memory stakeType,
        bool compounding
    ) external {
        require(amount >= minStakeAmount, "StakePoolFlex: UNDER_MINIMUM_STAKE_AMOUNT");
        _deposit(msg.sender, amount, stakeType, compounding);
    }

    /**
     * @dev Relock stakeToken.
     * Requirements:
     *
     * @param stakeId deposit amount.
     * @param stakeType string valid stakeType.
     * @param compounding bool is compounding.
     */

    function reLockStake(
        uint256 stakeId,
        string memory stakeType,
        bool compounding
    ) external {
        require(_exists(stakeId), "StakePoolFlex: STAKE_NOT_FOUND");
        require(msg.sender == ownerOf(stakeId), "StakePoolFlex: CALLER_NOT_TOKEN_OWNER");
        require(stakes[stakeId].lockedUntil < block.timestamp, "StakePoolFlex: STAKE_ALREADY_LOCKED");
        require(stakes[stakeId].amount >= minStakeAmount, "StakePoolFlex: UNDER_MINIMUM_STAKE_AMOUNT");
        _reLockStake(stakeId, stakeType, compounding);
    }

    /************************|
    |        Withdrawal      |
    |_______________________*/

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
    function withdraw(uint256 stakeId, uint256 amount) external {
        require(stakes[stakeId].lockedUntil < block.timestamp, "StakePoolFlex: STAKE_STILL_LOCKED_FOR_WITHDRAWAL");
        require(amount > 0, "StakePoolFlex: UNDER_MINIMUM_WITHDRAW_AMOUNT");
        _withdraw(msg.sender, stakeId, amount);
    }

    /**********************|
    |       Add Stakes     |
    |_____________________*/

    /**
     * @dev Add to stake.
     * Requirements:
     *
     * - `amount` must not be zero
     * @param stakeId stakeId
     * @param amount amount to add
     */
    function addStake(uint256 stakeId, uint256 amount) external nonReentrant {
        require(msg.sender == ownerOf(stakeId) || msg.sender == owner(), "StakePoolFlex: CALLER_NOT_TOKEN_OR_CONTRACT_OWNER");

        _addStake(stakeId, amount);
    }

    /**
     * @dev Add to stakes in batch.
     * Requirements:
     *
     * - `amount` must not be zero
     * @param stakeIds uint256[].
     * @param amounts uint256[].
     */
    function addStakes(uint256[] calldata stakeIds, uint256[] calldata amounts) external onlyOperator nonReentrant {
        _addStakes(stakeIds, amounts);
    }

    /**********************|
    |   Token StakeType    |
    |_____________________*/

    /**
     * @dev Returns the stakeType of a stakeToken
     * Requirements:
     *
     * @param stakeId uint256 stakeId.
     */
    function getStakeType(uint256 stakeId) external view returns (string memory) {
        require(_exists(stakeId), "StakePoolFlex: STAKE_NOT_FOUND");
        return stakes[stakeId].stakeType;
    }

    /**********************|
    |      Compound        |
    |_____________________*/

    /**
     * @dev Sets the composite value of a token to true or false
     * Requirements:
     *
     * @param tokenId uint256 stakeId.
     * @param compounding bool isCompounding.
     */
    function setCompounding(uint256 tokenId, bool compounding) external {
        require(msg.sender == ownerOf(tokenId), "StakePoolFlex: CALLER_NOT_TOKEN_OWNER");
        _setCompounding(tokenId, compounding);
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
    function depositReward(address rewardTokenAddress, uint256 amount) external onlyOperator {
        require(amount > 0, "StakePoolFlex: ZERO_AMOUNT");
        _depositReward(msg.sender, rewardTokenAddress, amount);
    }

    /**
     * @dev Return reward deposit info by id.
     * @param rewardTokenAddress reward token address
     */
    function getRewardDeposit(address rewardTokenAddress, uint256 id) external view returns (RewardDeposit memory) {
        return (rewardDeposits[rewardTokenAddress][id]);
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
        rewardClaims[tokenId].push(
            ClaimableRewardAddition({ operator: msg.sender, amount: amount, depositedAt: block.timestamp, rewardToken: rewardTokenAddress })
        );
        emit ClaimableRewardAdded(tokenId, rewardTokenAddress, amount);
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
            rewardClaims[tokenIds[i]].push(
                ClaimableRewardAddition({ operator: msg.sender, amount: amounts[i], depositedAt: block.timestamp, rewardToken: rewardTokenAddress })
            );
            emit ClaimableRewardAdded(tokenIds[i], rewardTokenAddress, amounts[i]);
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
        require((ownerOf(tokenId) == msg.sender), "StakePoolFlex: CALLER_NOT_TOKEN_OWNER");
        require(claimableRewards[rewardTokenAddress][tokenId] >= amount, "StakePoolFlex: INSUFFICIENT_FUNDS");
        claimableRewards[rewardTokenAddress][tokenId] -= amount;
        rewardTokens[rewardTokenAddress].safeTransfer(msg.sender, amount);
        emit RewardClaimed(msg.sender, rewardTokenAddress, amount);
    }

    /*************************|
    |     Sweept Funds        |
    |________________________*/

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
        require(rewardToken_ != address(0), "StakePoolFlex: ZERO_ADDRESS");
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
        string memory stakeType,
        bool compounding
    ) internal virtual nonReentrant {
        require(_validStakeType(stakeType), "StakePoolFlex: STAKE_TYPE_NOT_EXIST");
        uint256 depositedAt = block.timestamp;
        uint256 inDays = _getLockDays(stakeType);
        uint256 lockedUntil = block.timestamp + (inDays * 1 days);
        uint256 stakeId = _mint(account, amount, stakeType, depositedAt, lockedUntil, compounding);
        require(depositToken.transferFrom(account, address(this), amount), "StakePoolFlex: TRANSFER_FAILED");

        emit Deposited(account, stakeId, amount, lockedUntil);
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
    ) internal virtual nonReentrant {
        require(ownerOf(stakeId) == account, "StakePoolFlex: NO_STAKE_OWNER");
        _decreaseStakeAmount(stakeId, withdrawAmount);
        require(depositToken.transfer(account, withdrawAmount), "StakePoolFlex: TRANSFER_FAILED");

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
    ) internal virtual {
        rewardTokens[rewardTokenAddress].safeTransferFrom(account, address(this), amount);
        rewardDeposits[rewardTokenAddress].push(RewardDeposit({ operator: account, amount: amount, depositedAt: block.timestamp }));

        emit RewardDeposited(account, rewardTokenAddress, amount);
    }

    /**
     * @dev Add new reward token.
     * @param rewardToken_ reward token address.
     */
    function _addRewardToken(address rewardToken_) internal virtual {
        rewardTokens[rewardToken_] = IERC20(rewardToken_);
    }

    function _addStake(uint256 stakeId, uint256 amount) internal virtual {
        require(_exists(stakeId), "StakePoolFlex: STAKE_NOT_FOUND");
        require(amount > 0, "StakePoolFlex: INVALID_AMOUNT");

        require(depositToken.transferFrom(msg.sender, address(this), amount), "StakePoolFlex: TRANSFER_FAILED");
        stakes[stakeId].amount = stakes[stakeId].amount.add(amount);
        emit StakeAmountIncreased(stakeId, amount);
    }

    function _addStakes(uint256[] calldata stakeIds, uint256[] calldata amounts) internal virtual {
        require(stakeIds.length == amounts.length, "StakePoolFlex: DIFFERENT_LENGTHS");
        for (uint256 i = 0; i < stakeIds.length; i++) {
            require(_exists(stakeIds[i]), "StakePoolFlex: STAKE_NOT_FOUND");
            require(amounts[i] > 0, "StakePoolFlex: INVALID_AMOUNT");

            require(depositToken.transferFrom(msg.sender, address(this), amounts[i]), "StakePoolFlex: TRANSFER_FAILED");
            stakes[stakeIds[i]].amount = stakes[stakeIds[i]].amount.add(amounts[i]);
        }

        emit StakesAmountIncreased(stakeIds, amounts);
    }

    function _reLockStake(
        uint256 stakeId,
        string memory stakeType,
        bool compounding
    ) internal {
        uint256 inDays = _getLockDays(stakeType);

        stakes[stakeId].depositedAt = block.timestamp;
        stakes[stakeId].lockedUntil = block.timestamp + (inDays * 1 days);
        stakes[stakeId].isCompounding = compounding;

        emit Relocked(stakeId, stakeType, stakes[stakeId].amount);
    }
}
