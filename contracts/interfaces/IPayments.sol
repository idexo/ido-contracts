// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IStakeTokenMultipleRewards.sol";

interface IPayments is IReceipttoken {
    function payProduct(
        uint256 amount,
        uint256 productId
    )
        external;

    
}
