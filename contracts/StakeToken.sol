// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IStakeToken.sol";

contract StakeToken is IStakeToken, ERC721, Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    Counters.Counter internal _tokenIds;
    struct Stake {
        uint256 amount;
        uint256 multiplier; // should be divided by 100.
        uint256 depositedAt;
    }

    mapping(uint256 => Stake) internal _stakes;
    mapping(address => uint256[]) internal _stakerToIds;

    constructor(
        string memory name_,
        string memory symbol_
    )
        ERC721(name_, symbol_)
    { }

    /**
     * @dev Returns StakeToken multiplier.
     *
     * 0 < `tokenId` <300: 120.
     * 300 <= `tokenId` <4000: 110.
     * 4000 <= `tokenId`: 100.
     */
    function getMultiplier()
        public
        override
        view
        returns (uint256)
    {
        // This part is hard-coded now and may need update.
        if (_tokenIds.current() < 300) {
            return 120;
        } else if (300 <= _tokenIds.current() && _tokenIds.current() < 4000) {
            return 110;
        } else {
            return 100;
        }
    }

    /**
     * @dev Mint a new StakeToken.
     * @param account address of recipient.
     * @param amount mint amount.
     * @param depositedAt timestamp when stake was deposited.
     */
    function mint(
        address account,
        uint256 amount,
        uint256 depositedAt
    )
        public
        override
        virtual
        returns (uint256)
    {
        require(amount > 0, "StakeToken#mint: ZERO_AMOUNT");
        _tokenIds.increment();
        uint256 multiplier = getMultiplier();
        super._mint(account, _tokenIds.current());
        Stake storage newStake = _stakes[_tokenIds.current()];
        newStake.amount = amount;
        newStake.multiplier = multiplier;
        newStake.depositedAt = depositedAt;
        _stakerToIds[account].push(_tokenIds.current());

        return _tokenIds.current();
    }

    /**
     * @dev Burn stakeToken.
     * @param stakeId id of buring token.
     */
    function burn(
        uint256 stakeId
    )
        public
        override
        virtual
    {
        require(_exists(stakeId), "StakeToken#burn: STAKE_NOT_FOUND");
        address stakeOwner = ownerOf(stakeId);
        super._burn(stakeId);
        delete _stakes[stakeId];
        uint256[] storage stakeIds = _stakerToIds[stakeOwner];
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
     * @dev Get token id array owned by wallet address.
     * @param account address
     */
    function getTokenId(
        address account
    )
        public
        override
        view
        returns (uint256[] memory)
    {
        require(account != address(0), "StakeToken#getTokenId: ZERO_ADDRESS");
        return _stakerToIds[account];
    }

    /**
     * @dev Check if wallet address owns any tokens.
     * @param account address
     */
    function isTokenHolder(
        address account
    )
        public
        override
        view
        returns (bool)
    {
        require(account != address(0), "StakeToken#isTokenHolder: ZERO_ADDRESS");
        return balanceOf(account) > 0;
    }

    /**
     * @dev Return stake info from `stakeId`.
     * @param stakeId uint256
     */
    function getStake(
        uint256 stakeId
    )
        public
        override
        view
        returns (uint256, uint256, uint256)
    {
        require(_exists(stakeId), "StakeToken#getStake: STAKE_NOT_FOUND");
        return (_stakes[stakeId].amount, _stakes[stakeId].multiplier, _stakes[stakeId].depositedAt);
    }
}
