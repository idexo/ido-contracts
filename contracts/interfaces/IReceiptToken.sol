// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

struct Receipt {
    string productId;
    uint256 paidAmount;
    uint256 paidAt;
}

interface IReceiptToken is IERC721 {
    function getReceiptIds(address account) external returns (uint256[] memory);

    function getReceiptInfo(uint256 receiptId) external returns (Receipt memory);

    function receipts(uint256 id)
        external
        view
        returns (
            string memory productId,
            uint256 amount,
            uint256 paidAt
        );

    function payerIds(address account, uint256 id) external view returns (uint256);
}
