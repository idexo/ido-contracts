// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract StakeToken is ERC721, Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    Counters.Counter public _tokenIds;
    struct Stake {
        uint256 amount;
        uint256 multiplier; // should be divided by 100.
        uint256 depositedAt;
    }

    mapping(uint256 => Stake) public stakes;

    constructor(
        string memory name_,
        string memory symbol_
    )
        ERC721(name_, symbol_)
    {}

    /**
     * @dev Returns StakeToken multiplier.
     *
     * 0 < `tokenId` <300: 120.
     * 300 <= `tokenId` <4000: 110.
     * 4000 <= `tokenId`: 100.
     */
    function getMultiplier()
        public
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
        virtual
        returns (uint256)
    {
        require(amount > 0, "StakeToken#mint: ZERO_AMOUNT");
        _tokenIds.increment();
        uint256 multiplier = getMultiplier();
        super._mint(account, _tokenIds.current());
        Stake storage newStake = stakes[_tokenIds.current()];
        newStake.amount = amount;
        newStake.multiplier = multiplier;
        newStake.depositedAt = depositedAt;

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
        virtual
    {
        require(_exists(stakeId), "StakeToken#burn: STAKE_NOT_FOUND");
        super._burn(stakeId);
    }
}
