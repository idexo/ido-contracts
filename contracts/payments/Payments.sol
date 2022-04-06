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
        uint256 receiptId;
        uint256 purchasedAt;
    }

    // Products
    Product[] private _productsList;

    // Products Ids List
    string[] public productsList;

    // Products index
    mapping(string => uint256) productsIndex;

    // User purchases
    mapping(address => Purchased[]) public userPurchases;

    // User paid amount address => paymentToken => amount
    mapping(address => mapping(address => uint256)) private userTotalPaidAmount;

    event Paid(address indexed account, uint256 indexed receiptId, string productId, uint256 amount);
    event Refund(address indexed account, uint256 indexed receiptId, string productId, uint256 amount);
    event Swept(address indexed operator, address token, address indexed to, uint256 amount);

    constructor(
        string memory receiptTokenName_,
        string memory receiptTokenSymbol_,
        string memory receiptTokenBASEUri_,
        address paymentToken_
    ) ReceiptToken(receiptTokenName_, receiptTokenSymbol_, receiptTokenBASEUri_) {
        paymentTokens[paymentToken_] = IERC20(paymentToken_);
        _productsList.push(Product("DEFAULT", address(0), 0, false, 0));
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
        require(paymentToken_ != address(0), "Payments#addPayment: ZERO_ADDRESS");
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
        require(price_ > 0, "Payments#addProduct: ZERO_PRICE");
        _addProduct(productId_, paymentToken_, price_, openForSale_);
    }

    function setOpenForSale(string memory productId, bool openForSale) external onlyOperator {
        uint256 index = productsIndex[productId];
        require(index != 0, "Payments#setOpenForSale: INVALID_PRODUCT_ID");

        _productsList[index].openForSale = openForSale;
    }

    function getProducts() external view returns (string[] memory) {
        return productsList;
    }

    function getProduct(string memory productId) external view returns (Product[] memory) {
        uint256 index = productsIndex[productId];
        require(index != 0, "Payments#getProduct: INVALID_PRODUCT_ID");

        Product[] memory product = new Product[](1);
        product[0] = _productsList[index];
        return product;
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
        require(index != 0, "Payments#payProduct: INVALID_PRODUCT_ID");
        require(_productsList[index].openForSale, "Payments#payProduct: PRODUCT_UNAVAILABLE");

        address paymentToken = _productsList[index].paymentToken;
        uint256 price = _productsList[index].price;

        _payProduct(msg.sender, productId, price, paymentToken);
    }

    /************************|
    |         Purchased      |
    |_______________________*/

    /**
     * @dev Make payment to the pool for product.
     * Requirements:
     *
     * - `productId` must be exists
     * @param account deposit amount.
     */
    function getPurchased(address account) external view returns (Purchased[] memory purchased) {
        require(account != address(0), "Payments#getPurchased: ZERO_ADDRESS");
        return userPurchases[account];
    }

    /************************|
    |          Refund        |
    |_______________________*/

    /**
     * @dev Make refund.
     * Requirements:
     *
     * - `account` must be not zero
     * @param account deposit amount.
     * @param receiptId deposit amount.
     */
    function refund(address account, uint256 receiptId) external onlyOperator {
        require(account != address(0), "Payments#refund: ZERO_ADDRESS");
        IERC20 refundToken;

        _burn(receiptId);

        Purchased[] memory purchases = userPurchases[account];

        for (uint256 i = 0; i < purchases.length; i++) {
            if (purchases[i].receiptId == receiptId) {
                uint256 index = productsIndex[purchases[i].productId];
                refundToken = IERC20(_productsList[index].paymentToken);
                refundToken.transfer(account, _productsList[index].price);
                _popPurchase(account, i);
                userTotalPaidAmount[account][_productsList[index].paymentToken] -= _productsList[index].price;

                emit Refund(account, receiptId, _productsList[index].productId, _productsList[index].price);
                break;
            }
        }
    }

    /**
     * @dev Remove the purchase from userPurchases.

     // User paid amount
     mapping(address => mapping(address => uint256));
     *
     * @param from address from
     * @param purchaseIndex receiptId to remove
     */
    function _popPurchase(address from, uint256 purchaseIndex) internal {
        Purchased[] storage purchases = userPurchases[from];

        if (purchaseIndex != purchases.length - 1) {
            purchases[purchaseIndex] = purchases[purchases.length - 1];
        }
        purchases.pop();
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
        userPurchases[account].push(Purchased(productId, receiptId, paidAt));
        userTotalPaidAmount[account][paymentToken] += price;

        emit Paid(account, receiptId, productId, price);
    }

    function _addProduct(
        string memory productId,
        address paymentToken,
        uint256 price,
        bool openForSale
    ) internal virtual {
        _productsList.push(Product(productId, paymentToken, price, openForSale, block.timestamp));
        productsList.push(productId);
        productsIndex[productId] = _productsList.length - 1;
    }

    function _addPaymentToken(address paymentToken_) internal virtual {
        paymentTokens[paymentToken_] = IERC20(paymentToken_);
    }
}
