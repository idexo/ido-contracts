// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IStakeTokenSimple is IERC721 {
    function getStakerIds(address account) external view returns (uint256[] memory);

    function getStakeAmount(address account) external view returns (uint256);

    function isHolder(address account) external view returns (bool);

    function getEligibleStakeAmount(uint256 fromDate) external view returns (uint256);

    function stakes(uint256 id) external view returns (uint256 amount, uint256 multiplier, uint256 depositedAt);

    function stakerIds(address account, uint256 id) external view returns (uint256);

    function create(address account, uint256 amount, uint256 depositedAt) external returns (uint256);

    function decreaseStakeAmount(uint256 stakeId, uint256 amount) external;
}
