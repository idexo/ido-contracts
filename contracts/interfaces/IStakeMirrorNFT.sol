// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IStakeMirrorNFT is IERC721 {
    function getStakerIds(address account) external view returns (uint256[] memory);

    function isHolder(address account) external view returns (bool);

    function stakes(uint256 id) external view returns (uint256 amount, uint256 multiplier, uint256 depositedAt);

    function stakerIds(address account, uint256 id) external view returns (uint256);

    function addOperator(address account) external;

    function removeOperator(address account) external;

    function checkOperator(address account) external view returns (bool);
}
