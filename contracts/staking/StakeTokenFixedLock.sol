// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../lib/Operatorable.sol";

contract StakeTokenFixedLock is ERC721URIStorage, Operatorable, ReentrancyGuard {
    using SafeMath for uint256;
    IERC20 public stakingToken;
    uint256 constant YEAR = 365 days;

    // Holds the accumulated reward claimed for a stake token
    mapping(uint256 => uint256) private rewardsClaimed;

    // Available rewards in deposit token to be withdrawn from when claiming
    uint256 public availableRewards;

    // Last stake token id, start from 1
    uint256 public tokenIds;
    uint256 public currentSupply;

    // Base NFT URI
    string public baseURI;

    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 period;
        uint256 rate;
    }

    // stake id => stake info
    mapping(uint256 => Stake) public stakes;
    // staker wallet => stake id array
    mapping(address => uint256[]) public stakerIds;

    event Swept(address indexed operator, address token, address indexed to, uint256 amount);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address _stakingToken
    ) ERC721(name_, symbol_) {
        baseURI = baseURI_;
        stakingToken = IERC20(_stakingToken);
    }

    function stake(uint256 _amount, uint256 _period) public nonReentrant {
        require(_amount > 0, "STAKE_TOKEN_FIXED_LOCK#Cannot_stake_0");

        // Calculate rate based on period
        uint256 rate;
        if (_period == 45) {
            rate = 2;
        } else if (_period == 60) {
            rate = 3;
        } else if (_period == 90) {
            rate = 5;
        } else if (_period == 120) {
            rate = 8;
        } else if (_period == 180) {
            rate = 12;
        } else if (_period == 360) {
            rate = 30;
        } else {
            revert("STAKE_TOKEN_FIXED_LOCK#Invalid_staking_period");
        }

        // Transfer the staking tokens to this contract
        stakingToken.transferFrom(msg.sender, address(this), _amount);

        _mint(msg.sender, _amount, block.timestamp, _period, rate);
       
    }

     function calculateReward(Stake storage _stake) internal view returns (uint256) {
        uint256 timeDiff = block.timestamp - _stake.timestamp;
        uint256 reward = _stake.amount.mul(_stake.rate).mul(timeDiff).div(YEAR).div(100);
        return reward;
    }

    function getAvailableClaim(uint256 _tokenId) public view returns (uint256) {
       
        require(_exists(_tokenId), "STAKE_TOKEN_FIXED_LOCK#ERC721_operator_query_for_nonexistent_token");

        Stake storage stake = stakes[_tokenId];
        uint256 totalReward = calculateReward(stake);
        uint256 alreadyClaimed = rewardsClaimed[_tokenId];

        if (alreadyClaimed >= totalReward) {
            return 0;
        } else {
            return totalReward - alreadyClaimed;
        }
    }
    

    function claim(uint256 _tokenId) public nonReentrant {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "STAKE_TOKEN_FIXED_LOCK#Not_owner_nor_approved");

        Stake storage stake = stakes[_tokenId];
        uint256 totalReward = calculateReward(stake);
        uint256 alreadyClaimed = rewardsClaimed[_tokenId];

        uint256 claimable;
        if (alreadyClaimed >= totalReward) {
            claimable = 0;
        } else {
            claimable = totalReward - alreadyClaimed;
        }

        if (claimable > 0) {
            require(availableRewards >= claimable, "STAKE_TOKEN_FIXED_LOCK#Not_enough_rewards_available");

            rewardsClaimed[_tokenId] += claimable;

            // Transfer the reward tokens to the staker
            stakingToken.transfer(msg.sender, claimable);

            availableRewards -=claimable;
        }

        // Reset timestamp to now
        stake.timestamp = block.timestamp;
    }

    function withdraw(uint256 _tokenId) public nonReentrant {
            require(_isApprovedOrOwner(msg.sender, _tokenId), "STAKE_TOKEN_FIXED_LOCK#Not_owner_nor_approved");

            Stake storage stake = stakes[_tokenId];

            // Ensure the stake period has passed
            require(block.timestamp >= stake.timestamp + (stake.period * 1 days), "STAKE_TOKEN_FIXED_LOCK#Staking_period_not_passed");

            uint256 totalReward = calculateReward(stake);
            uint256 alreadyClaimed = rewardsClaimed[_tokenId];

            uint256 claimable;
            if (alreadyClaimed >= totalReward) {
                claimable = 0;
            } else {
                claimable = totalReward - alreadyClaimed;
            }

            if (claimable > 0) {
                // Transfer the reward tokens to the staker
                stakingToken.transfer(msg.sender, claimable);

                availableRewards -=claimable;
            }

            uint256 amount = stake.amount;

            // Destroy the NFT for the stake
            _burn(_tokenId);

            // Transfer the staked tokens back to the staker
            stakingToken.transfer(msg.sender, amount);
    }

    /**
     * @dev Override supportInterface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**********************|
    |          URI         |
    |_____________________*/

    /**
     * @dev Return token URI
     * Override {ERC721URIStorage:tokenURI}
     */
    function tokenURI(uint256 tokenId) public view override(ERC721URIStorage) returns (string memory) {
        return ERC721URIStorage.tokenURI(tokenId);
    }

    /**
     * @dev Set token URI
     * Only `operator` can call
     *
     * - `tokenId` must exist, see {ERC721URIStorage:_setTokenURI}
     */
    function setTokenURI(uint256 tokenId, string memory _tokenURI) public onlyOwner {
        super._setTokenURI(tokenId, _tokenURI);
    }

    /**
     * @dev Set `baseURI`
     * Only `operator` can call
     */
    function setBaseURI(string memory baseURI_) public onlyOwner {
        baseURI = baseURI_;
    }


    /**********************|
    |       Stake Info     |
    |_____________________*/

    /**
     * @dev Get stake token id array owned by wallet address.
     * @param account address
     */
    function getStakeTokenIds(address account) public view returns (uint256[] memory) {
        return stakerIds[account];
    }

    /**
     * @dev Return total stake amount of `account`
     * @param account address
     */
    function getStakeAmount(address account) external view returns (uint256) {
        uint256[] memory stakeIds = stakerIds[account];
        uint256 totalStakeAmount;
        for (uint256 i = 0; i < stakeIds.length; i++) {
            totalStakeAmount += stakes[stakeIds[i]].amount;
        }
        return totalStakeAmount;
    }

    /**
     * @dev Check if wallet address owns any stake tokens.
     * @param account address
     */
    function isHolder(address account) public view returns (bool) {
        return balanceOf(account) > 0;
    }

    /**
     * @dev Return stake info from `stakeId`.
     * Requirements:
     *
     * - `stakeId` must exist in stake pool
     * @param stakeId uint256
     */
    function getStakeInfo(uint256 stakeId) public view returns (Stake memory) {
        require(_exists(stakeId), "STAKE_TOKEN_FIXED_LOCK#STAKE_NOT_FOUND");
        return (stakes[stakeId]);
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
    function depositReward(uint256 amount) external {
        require(amount > 0, "STAKE_TOKEN_FIXED_LOCK#ZERO_AMOUNT");
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        availableRewards += amount;
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
    |   Private Functions     |
    |________________________*/

    /**
     * @dev Return base URI
     * Override {ERC721:_baseURI}
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Remove the given token from stakerIds.
     *
     * @param from address from
     * @param tokenId tokenId to remove
     */
    function _popStake(address from, uint256 tokenId) internal {
        uint256[] storage stakeIds = stakerIds[from];
        for (uint256 i = 0; i < stakeIds.length; i++) {
            if (stakeIds[i] == tokenId) {
                if (i != stakeIds.length - 1) {
                    stakeIds[i] = stakeIds[stakeIds.length - 1];
                }
                stakeIds.pop();
                break;
            }
        }
    }



    /**
     * @dev Mint a new StakeToken.
     * Requirements:
     *
     * - `account` must not be zero address, check ERC721 {_mint}
     * - `amount` must not be zero
     * @param account address of recipient.
     * @param amount mint amount.
     * @param timestamp timestamp when stake was deposited.
     * @param period time period for which stake was deposited
     * @param rate the rate applied for APR
     */
    function _mint(
        address account,
        uint256 amount,
        uint256 timestamp,
        uint256 period,
        uint256 rate
    ) internal virtual returns (uint256) {
        require(amount > 0, "STAKE_TOKEN_FIXED_LOCK#INVALID_AMOUNT");

        tokenIds += 1;
        currentSupply += 1;
        super._mint(account, tokenIds);
        Stake storage newStake = stakes[tokenIds];
        newStake.amount = amount;
        newStake.timestamp = timestamp;
        newStake.period = period;
        newStake.rate = rate;

        stakerIds[account].push(tokenIds);
        return tokenIds;
    }


    /**
     * @dev Burn stakeToken.
     * Requirements:
     *
     * - `stakeId` must exist in stake pool
     * @param stakeId id of buring token.
     */
    function _burn(uint256 stakeId) internal override(ERC721URIStorage) {
        require(_exists(stakeId), "STAKE_TOKEN_FIXED_LOCK#STAKE_NOT_FOUND");
        address stakeOwner = ownerOf(stakeId);
        super._burn(stakeId);
        delete stakes[stakeId];
        currentSupply -= 1;
        _popStake(stakeOwner, stakeId);
    }

  

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * @param from address from
     * @param to address to
     * @param tokenId tokenId to transfer
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        super._transfer(from, to, tokenId);
        _popStake(from, tokenId);
        stakerIds[to].push(tokenId);
    }
}
