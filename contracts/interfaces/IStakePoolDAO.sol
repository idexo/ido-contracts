// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IStakeTokenDAO.sol";

interface IStakePoolDAO is IStakeTokenDAO {
    function deposit(
        uint256 amount
    )
        external;

    function withdraw(
        uint256 stakeId,
        uint256 amount
    )
        external;

}
