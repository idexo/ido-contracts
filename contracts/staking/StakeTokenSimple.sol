// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IStakeTokenSimple.sol";

contract StakeTokenSimple is IStakeTokenSimple, ERC721, Ownable {
    // Last stake token id, start from 1
    uint256 public tokenID;
    uint256 public constant multiplierDenominator = 100;
    // Stake pool address
    address public stakePoolSimple;

    struct Stake {
        uint256 amount;
        uint256 multiplier;
        uint256 depositedAt;
    }
    // stake id => stake info
    mapping(uint256 => Stake) public override stakes;
    // staker wallet => stake id array
    mapping(address => uint256[]) public override stakerIds;

    event StakeAmountDecreased(uint256 stakeId, uint256 decreaseAmount);

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) { }

    /**
     * @dev Get stake token id array owned by `account`.
     */
    function getStakerIds(address account) external override view returns (uint256[] memory) {
        return stakerIds[account];
    }

    /**
     * @dev Return total stake amount of `account`
     */
    function getStakeAmount(address account) external override view returns (uint256 totalStakeAmount) {
        uint256[] memory stakeIds = stakerIds[account];
        for (uint256 i = 0; i < stakeIds.length; i++) {
            totalStakeAmount += stakes[stakeIds[i]].amount;
        }
    }

    /**
     * @dev Check if `account` owns any stake tokens.
     */
    function isHolder(address account) public override view returns (bool) {
        return balanceOf(account) > 0;
    }

    /**
     * @dev Return total stake amount that have been in the pool from `fromDate`
     *
     * - `fromDate` must be past date
     */
    function getEligibleStakeAmount(uint256 fromDate) public override view returns (uint256 totalSAmount) {
        require(fromDate < block.timestamp, "StakeTokenSimple: NO_PAST_DATE");
        for (uint256 i = 1; i <= tokenID; i++) {
            if (_exists(i)) {
                Stake memory stake = stakes[i];
                if (stake.depositedAt > fromDate) {
                    break;
                }
                totalSAmount += stake.amount * stake.multiplier / multiplierDenominator;
            }
        }
    }

    /**
     * @dev Returns StakeToken multiplier.
     *
     * `tokenID` <300: 120.
     * 300 <= `tokenID` <4000: 110.
     * 4000 <= `tokenID`: 100.
     */
    function _getMultiplier() private view returns (uint256) {
        if (tokenID < 300) {
            return 120;
        } else if (300 <= tokenID && tokenID < 4000) {
            return 110;
        } else {
            return 100;
        }
    }

    /**
     * @dev Set StakePoolSimple address
     *
     * - `_stakePoolSimple` must not be zero address
     */
    function setStakePoolSimple(address _stakePoolSimple) external onlyOwner {
        require(_stakePoolSimple != address(0), "StakeTokenSimple: ADDRESS_INVALID");
        stakePoolSimple = _stakePoolSimple;
    }

    /**
     * @dev Create a new StakeToken.
     *
     * - `account` must not be zero address, check ERC721 {_mint}
     * - `amount` must not be zero
     */
    function create(
        address account,
        uint256 amount,
        uint256 depositedAt
    ) public override returns (uint256) {
        require(_msgSender() == stakePoolSimple, "StakeTokenSimple: CALLER_NO_STAKE_POOL_SIMPLE");
        require(amount > 0, "StakeTokenSimple: INVALID_AMOUNT");
        tokenID++;
        uint256 multiplier = _getMultiplier();
        super._mint(account, tokenID);
        Stake storage newStake = stakes[tokenID];
        newStake.amount = amount;
        newStake.multiplier = multiplier;
        newStake.depositedAt = depositedAt;
        stakerIds[account].push(tokenID);

        return tokenID;
    }

    /**
     * @dev Burn StakeToken.
     *
     * - `stakeId` must exist in stake pool
     */
    function _burn(uint256 stakeId) internal override {
        require(_exists(stakeId), "StakeTokenSimple: STAKE_NOT_FOUND");
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
     * @dev Decrease stake amount by `amount`.
     * If stake amount leads to be zero, the stake is burned.
     *
     * - `stakeId` must be valid
     */
    function decreaseStakeAmount(
        uint256 stakeId,
        uint256 amount
    ) external override {
        require(_msgSender() == stakePoolSimple, "StakeTokenSimple: CALLER_NO_STAKE_POOL_SIMPLE");
        require(_exists(stakeId), "StakeTokenSimple: STAKE_NOT_FOUND");
        require(amount <= stakes[stakeId].amount, "StakeTokenSimple: INSUFFICIENT_STAKE_AMOUNT");
        if (amount == stakes[stakeId].amount) {
            _burn(stakeId);
        } else {
            stakes[stakeId].amount -= amount;
            emit StakeAmountDecreased(stakeId, amount);
        }
    }
}
