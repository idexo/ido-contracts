// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IStakeToken.sol";

interface IStakePool is IStakeToken {
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
        uint256 amount
    )
        external;

    function withdrawStake(
        uint256 stakeId,
        uint256 amount
    )
        external;

    function getUnlockedRevenueShare()
        external
        returns (uint256);

    function withdrawRevenueShare(
        uint256 amount
    )
        external;

    function depositRevenueShare(
        uint256 amount
    )
        external;

    function updateStakeClaimShares(
        uint256 fromDate
    )
        external
        returns (uint256[] memory, uint256);

    function distribute()
        external;

    function sumDeposits(
        uint256 fromDate
    )
        external
        returns (uint256);
}
