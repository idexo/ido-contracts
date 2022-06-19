// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IStakeTokenFlexLock is IERC721 {
    function getStakeTokenIds(address account) external returns (uint256[] memory);

    function isHolder(address account) external returns (bool);

    function getStakeInfo(uint256 stakeId)
        external
        returns (
            uint256,
            string memory,
            uint256,
            uint256,
            bool
        );

    function getEligibleStakeAmount(uint256 fromDate) external returns (uint256);

    function stakes(uint256 id)
        external
        view
        returns (
            uint256 amount,
            string memory stakeType,
            uint256 depositedAt,
            uint256 blockedUntil,
            bool compounding
        );

    function stakerIds(address account, uint256 id) external view returns (uint256);
}
