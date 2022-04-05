// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IReceiptToken is IERC721 {
    function getReceiptIds(
        address account
    )
        external
        returns (uint256[] memory);

    function hasPaid(
        address account
    )
        external
        returns (bool);

    function getReceiptInfo(
        uint256 receiptId
    )
        external
        returns (uint256, uint256, uint256);


    function stakes(uint256 id) external view returns (uint256 amount, uint256 multiplier, uint256 depositedAt, uint256 timestamplock);

    function stakerIds(address account, uint256 id) external view returns (uint256);
}
