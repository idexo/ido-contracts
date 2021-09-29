// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IStakeToken is IERC721 {
    function isHolder(address account) external returns (bool);

    function getEligibleStakeAmount(uint256 fromDate) external returns (uint256);
}
