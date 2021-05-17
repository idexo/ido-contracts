// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract StakeToken is Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    Counters.Counter private _totalStakes;
    struct Stake {
        uint256 amount;
        uint256 multiplier; // should be divided by 100
        uint256 depositedAt;
    }

    mapping(address => mapping(uint256 => Stake)) internal _stakes;
    mapping(address => uint256) internal _lastStakeIds;

    constructor() public {}

    modifier onlyStaker(
        address account
    ) {
        require(_lastStakeIds[account] > 0, "StakeToken: not staker");
        _;
    }

    function _getMultiplier()
        private
        view
        returns (uint256)
    {
        // This part is hard-coded now and needs update
        if (_totalStakes.current() <= 300) {
            return 120;
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
        _totalStakes.increment();
        uint256 multiplier = _getMultiplier();
        uint256 id = ++_lastStakeIds[account];
        Stake storage newStake = _stakes[account][id];
        newStake.amount = amount;
        newStake.multiplier = multiplier;
        newStake.depositedAt = depositedAt;

        return id;
    }

    // function burn(
    //     uint256 stakeId
    // )
    //     internal
    //     virtual
    // {
    //     // ERC721 checks if owner of stakeId exists in ownerOf method
    //     require(_lastStakeIds[msg.sender] != 0, "StakeToken: no staker");
    //     delete _stakes[stakeId];
    //     super._burn(stakeId);
    // }
}
