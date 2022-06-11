// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IStakeTokenFlexLock.sol";

interface IStakePoolFlexLock is IStakeTokenFlexLock {
    function deposit(uint256 amount, string memory depositType) external;

    function withdraw(uint256 stakeId, uint256 amount) external;

    function depositReward(address rewardTokenAddress, uint256 amount) external;
}
