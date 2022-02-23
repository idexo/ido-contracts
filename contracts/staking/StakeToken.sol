// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IStakeToken.sol";
import "../lib/StakeMath.sol";

contract StakeToken is IStakeToken, ERC721, Ownable {
    using SafeMath for uint256;
    using StakeMath for uint256;
    // Last stake token id, start from 1
    uint256 public tokenIds;
    uint256 public constant multiplierDenominator = 100;

    struct Stake {
        uint256 amount;
        uint256 multiplier;
        uint256 depositedAt;
    }
    // stake id => stake info
    mapping(uint256 => Stake) public stakes;
    // staker wallet => stake id array
    mapping(address => uint256[]) public stakerIds;

    event StakeAmountDecreased(uint256 stakeId, uint256 decreaseAmount);

    constructor(
        string memory name_,
        string memory symbol_
    )
        ERC721(name_, symbol_)
    { }

    /**
     * @dev Get stake token id array owned by wallet address.
     * @param account address
     */
    function getStakeTokenIds(
        address account
    )
        public
        override
        view
        returns (uint256[] memory)
    {
        return stakerIds[account];
    }

    /**
     * @dev Return total stake amount of `account`
     */
    function getStakeAmount(
        address account
    )
        external
        view
        returns (uint256)
    {
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
    function isHolder(
        address account
    )
        public
        override
        view
        returns (bool)
    {
        return balanceOf(account) > 0;
    }

    /**
     * @dev Return stake info from `stakeId`.
     * Requirements:
     *
     * - `stakeId` must exist in stake pool
     * @param stakeId uint256
     */
    function getStakeInfo(
        uint256 stakeId
    )
        public
        override
        view
        returns (uint256, uint256, uint256)
    {
        require(_exists(stakeId), "StakeToken#getStakeInfo: STAKE_NOT_FOUND");
        return (stakes[stakeId].amount, stakes[stakeId].multiplier, stakes[stakeId].depositedAt);
    }

    /**
     * @dev Return total stake amount that have been in the pool from `fromDate`
     * Requirements:
     *
     * - `fromDate` must be past date
     */
    function getEligibleStakeAmount(
        uint256 fromDate
    )
        public
        override
        view
        returns (uint256)
    {
        require(fromDate <= block.timestamp, "StakeToken#getEligibleStakeAmount: NO_PAST_DATE");
        uint256 totalSAmount;

        for (uint256 i = 1; i <= tokenIds; i++) {
            if (_exists(i)) {
                Stake memory stake = stakes[i];
                if (stake.depositedAt > fromDate) {
                    break;
                }
                totalSAmount += stake.amount * stake.multiplier / multiplierDenominator;
            }
        }

        return totalSAmount;
    }

    /**
     * @dev Mint a new StakeToken.
     * Requirements:
     *
     * - `account` must not be zero address, check ERC721 {_mint}
     * - `amount` must not be zero
     * @param account address of recipient.
     * @param amount mint amount.
     * @param depositedAt timestamp when stake was deposited.
     */
    function _mint(
        address account,
        uint256 amount,
        uint256 depositedAt
    )
        internal
        virtual
        returns (uint256)
    {
        require(amount > 0, "StakeToken#_mint: INVALID_AMOUNT");
        tokenIds++;
        super._mint(account, tokenIds);
        Stake storage newStake = stakes[tokenIds];
        newStake.amount = amount;
        newStake.multiplier = tokenIds.multiplier();
        newStake.depositedAt = depositedAt;
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
    function _burn(
        uint256 stakeId
    )
        internal
        override
    {
        require(_exists(stakeId), "StakeToken#_burn: STAKE_NOT_FOUND");
        address stakeOwner = ownerOf(stakeId);
        super._burn(stakeId);
        delete stakes[stakeId];
        uint256[] storage stakeIds = stakerIds[stakeOwner];
        for (uint256 i = 0; i < stakeIds.length; i++) {
            if (stakeIds[i] == stakeId) {
                if (i != stakeIds.length - 1) {
                    stakeIds[i] = stakeIds[stakeIds.length - 1];
                }
                stakeIds.pop();
                break;
            }
        }
    }

    /**
     * @dev Decrease stake amount.
     * If stake amount leads to be zero, the stake is burned.
     * Requirements:
     *
     * - `stakeId` must exist in stake pool
     * @param stakeId id of buring token.
     * @param amount to withdraw.
     */
    function _decreaseStakeAmount(
        uint256 stakeId,
        uint256 amount
    )
        internal
        virtual
    {
        require(_exists(stakeId), "StakeToken#_decreaseStakeAmount: STAKE_NOT_FOUND");
        require(amount <= stakes[stakeId].amount, "StakeToken#_decreaseStakeAmount: INSUFFICIENT_STAKE_AMOUNT");
        if (amount == stakes[stakeId].amount) {
            _burn(stakeId);
        } else {
            stakes[stakeId].amount = stakes[stakeId].amount.sub(amount);
            emit StakeAmountDecreased(stakeId, amount);
        }
    }
}
