// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IStakeToken is IERC721 {
    function getTokenId(
        address account
    )
        external
        returns (uint256[] memory);

    function isTokenHolder(
        address account
    )
        external
        returns (bool);

    function getStake(
        uint256 stakeId
    )
        external
        returns (uint256, uint256, uint256);
}
