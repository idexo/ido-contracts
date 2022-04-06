// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ReceiptToken.sol";
import "../interfaces/IPayments.sol";

contract Payments is IPayments, ReceiptToken, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Address of payment token.
    IERC20 public paymentToken;

    // // Stubbing out ability to have more than one payment token
    // // would need to specify the number of decimals to differentiate
    // // ones with different decimals
    // mapping(address => IERC20) public paymentTokens;

    event Paid(address indexed account, uint256 indexed receiptId, string productId, uint256 amount);
    event Swept(address indexed operator, address token, address indexed to, uint256 amount);

    constructor(
        string memory receiptTokenName_,
        string memory receiptTokenSymbol_,
        string memory receiptTokenBASEUri_,
        IERC20 paymentToken_
    ) ReceiptToken(receiptTokenName_, receiptTokenSymbol_, receiptTokenBASEUri_) {
        paymentToken = paymentToken_;
    }

    /************************|
    |          Payment       |
    |_______________________*/

    /**
     * @dev Make payment to the pool for product.
     * Requirements:
     *
     * - `amount` must not be zero
     * @param amount deposit amount.
     */
    function payProduct(string memory productId, uint256 amount) external override {
        _payProduct(msg.sender, productId, amount);
    }

    /**
     * @dev Sweep funds
     * Accessible by operators
     */
    function sweep(
        address token_,
        address to,
        uint256 amount
    ) public onlyOperator {
        IERC20 token = IERC20(token_);
        // balance check is being done in ERC20
        token.transfer(to, amount);
        emit Swept(msg.sender, token_, to, amount);
    }

    /*************************|
    |   Internal Functions     |
    |________________________*/

    /**
     * @dev Deposit stake to the pool.
     * @param account address of recipient.
     * @param amount deposit amount.
     */
    function _payProduct(
        address account,
        string memory productId,
        uint256 amount
    ) internal virtual nonReentrant {
        uint256 paidAt = block.timestamp;
        uint256 receiptId = _mint(account, productId, amount, paidAt);
        // require(paymentToken.safeTransferFrom(account, address(this), amount), "Payments#_payProduct: TRANSFER_FAILED");

        emit Paid(account, receiptId, productId, amount);
    }
}
