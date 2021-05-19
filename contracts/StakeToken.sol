// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract StakeToken is ERC721, Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    Counters.Counter internal _tokenIds;
    struct Stake {
        uint256 amount;
        uint256 multiplier; // should be divided by 100
        uint256 depositedAt;
    }

    mapping(uint256 => Stake) internal _stakes;

    constructor(
        string memory name_,
        string memory symbol_
    )
        ERC721(name_, symbol_)
    {}

    function _getMultiplier()
        private
        view
        returns (uint256)
    {
        // This part is hard-coded now and needs update
        if (_tokenIds.current() < 300) {
            return 120;
        } else if (300 <= _tokenIds.current() && _tokenIds.current() < 4000) {
            return 110;
        } else {
            return 100;
        }
    }

    function _mint(
        address account,
        uint256 amount,
        uint256 depositedAt
    )
        internal
        virtual
        returns (uint256)
    {
        require(amount >= 0, "StakeToken: amount should not be 0");
        _tokenIds.increment();
        uint256 multiplier = _getMultiplier();
        super._mint(account, _tokenIds.current());
        Stake storage newStake = _stakes[_tokenIds.current()];
        newStake.amount = amount;
        newStake.multiplier = multiplier;
        newStake.depositedAt = depositedAt;

        return _tokenIds.current();
    }

    function _burn(
        uint256 stakeId
    )
        internal
        virtual
        override
    {
        require(_exists(stakeId), "StakeToken: stake not found");
        super._burn(stakeId);
    }
}
