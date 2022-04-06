// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IReceiptToken.sol";

interface IPayments is IReceiptToken {
    function payProduct(
        string memory productId
    )
        external;

    
}
