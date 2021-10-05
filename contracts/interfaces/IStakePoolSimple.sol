// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface IStakePoolSimple {
    function addOperator(address account) external;

    function removeOperator(address account) external;

    function checkOperator(address account) external view returns (bool);

    function deposit(uint256 amount) external;

    function withdraw(uint256 stakeId, uint256 amount) external;
}
