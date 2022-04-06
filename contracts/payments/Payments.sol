// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ReceiptToken.sol";
import "../interfaces/IPayments.sol";

contract Payments is IPayments, ReceiptToken, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Mapping of payment tokens.
    mapping(address => IERC20) public paymentTokens;

    // Timestamp when contract was deployed to mainnet.
    uint256 public deployedAt;

    struct Product {
        string productId;
        address paymentToken;
        uint256 price;
        bool openForSale;
        uint256 insertedAt;
    }

    struct Purchased {
        string productId;
        uint256 purchasedAt;
    }

    // Products
    Product[] private _productsList;

    // Products index
    mapping(string => uint256) productsIndex;

    // User purchases
    mapping(address => Purchased[]) public purchasedProducts;

    event Paid(address indexed account, uint256 indexed receiptId, string productId, uint256 amount);
    event Swept(address indexed operator, address token, address indexed to, uint256 amount);

    constructor(
        string memory receiptTokenName_,
        string memory receiptTokenSymbol_,
        string memory receiptTokenBASEUri_,
        address paymentToken_
    ) ReceiptToken(receiptTokenName_, receiptTokenSymbol_, receiptTokenBASEUri_) {
        paymentTokens[paymentToken_] = IERC20(paymentToken_);
        _productsList.push(Product({ productId: "NOT_FOUND", paymentToken: address(0), price: 0, openForSale: false, insertedAt: 0 }));
        deployedAt = block.timestamp;
    }

    /*************************|
    |     Payment Tokens      |
    |________________________*/

    /**
     * @dev Add new payment token.
     * @param paymentToken_ payment token address.
     */
    function addPaymentToken(address paymentToken_) public onlyOperator {
        require(paymentToken_ != address(0), "Payment#_addPayment: ZERO_ADDRESS");
        _addPaymentToken(paymentToken_);
    }

    /*************************|
    |         Product         |
    |________________________*/

    /**
     * @dev Add a new product.
     * Requirements:
     *
     * - `price` must not be zero
     * @param productId_ productId.
     * @param paymentToken_ address paymentToken.
     * @param price_ price in wei, considering the token decimals
     * @param openForSale_ product available
     */
    function addProduct(
        string memory productId_,
        address paymentToken_,
        uint256 price_,
        bool openForSale_
    ) external onlyOperator {
        require(price_ > 0, "Payment#addProduct: ZERO_PRICE");
        _addProduct(productId_, paymentToken_, price_, openForSale_);
    }

    function getProductList() external view returns (Product[] memory) {
        return _productsList;
    }

    /************************|
    |          Payment       |
    |_______________________*/

    /**
     * @dev Make payment to the pool for product.
     * Requirements:
     *
     * - `productId` must be exists
     * @param productId deposit amount.
     */
    function payProduct(string memory productId) external override {
        uint256 index = productsIndex[productId];
        require(index != 0, "INVALID_PRODUCT_ID");

        address paymentToken = _productsList[index].paymentToken;
        uint256 price = _productsList[index].price;

        _payProduct(msg.sender, productId, price, paymentToken);
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
     * @param price deposit amount.
     */
    function _payProduct(
        address account,
        string memory productId,
        uint256 price,
        address paymentToken
    ) internal virtual nonReentrant {
        IERC20 pToken = IERC20(paymentToken);
        uint256 paidAt = block.timestamp;
        // check this require
        // it seems that safeTransferFrom already verifies the correct execution of the transfer.
        // Does not work with require

        // require(pToken.safeTransferFrom(account, address(this), price), "Payments#_payProduct: TRANSFER_FAILED");
        pToken.safeTransferFrom(account, address(this), price);

        uint256 receiptId = _mint(account, productId, price, paidAt);

        emit Paid(account, receiptId, productId, price);
    }

    function _addProduct(
        string memory productId,
        address paymentToken,
        uint256 price,
        bool openForSale
    ) internal virtual {
        _productsList.push(
            Product({ productId: productId, paymentToken: paymentToken, price: price, openForSale: openForSale, insertedAt: block.timestamp })
        );
        productsIndex[productId] = _productsList.length - 1;
    }

    function _addPaymentToken(address paymentToken_) internal virtual {
        paymentTokens[paymentToken_] = IERC20(paymentToken_);
    }
}
