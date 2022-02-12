// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IStakeTokenMultipleRewardsV1.sol";

interface IStakePoolMultipleRewardsV1 is IStakeTokenMultipleRewardsV1 {
    function addOperator(
        address account
    )
        external;

    function removeOperator(
        address account
    )
        external;

    function checkOperator(
        address account
    )
        external
        returns (bool);

    function deposit(
        uint256 amount,
        uint256 timestamplock
    )
        external;

    function withdraw(
        uint256 stakeId,
        uint256 amount
    )
        external;


    function depositReward(
        address rewardTokenAddress,
        uint256 amount
    )
        external;


}
