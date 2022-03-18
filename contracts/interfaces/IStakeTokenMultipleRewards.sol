// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IStakeTokenMultipleRewards is IERC721 {
    function getStakeTokenIds(
        address account
    )
        external
        returns (uint256[] memory);

    function isHolder(
        address account
    )
        external
        returns (bool);

    function getStakeInfo(
        uint256 stakeId
    )
        external
        returns (uint256, uint256, uint256, uint256);

    function getEligibleStakeAmount(
        uint256 fromDate
    )
        external
        returns (uint256);

    function stakes(uint256 id) external view returns (uint256 amount, uint256 multiplier, uint256 depositedAt, uint256 timestamplock);

    function stakerIds(address account, uint256 id) external view returns (uint256);
}
