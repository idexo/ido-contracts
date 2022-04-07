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
        uint256 amount;
        uint256 purchasedAt;
    }

    // Products
    Product[] private _products;

    // Products Ids List
    string[] public productsList;

    // Products index
    mapping(string => uint256) productsIndex;

    // User purchases
    mapping(address => Purchased[]) public userPurchases;

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
        _products.push(Product("DEFAULT", address(0), 0, false, 0));
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
     * - `price_` must not be zero
     * @param productId_ productId
     * @param paymentToken_ address paymentToken
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

    /**
     * @dev Product sale status.
     * Requirements:
     * - `productId_` must be exists
     * @param productId_ productId.
     * @param openForSale_ product available for sale
     */
    function setOpenForSale(string memory productId_, bool openForSale_) external onlyOperator {
        uint256 index = productsIndex[productId_];
        require(index != 0, "Payments#setOpenForSale: INVALID_PRODUCT_ID");
        _products[index].openForSale = openForSale_;
    }

    /**
     * @dev Set new product price.
     * Requirements:
     * - `productId_` must be exists
     * @param productId_ productId.
     * @param newPrice_ product available
     */
    function setPrice(string memory productId_, uint256 newPrice_) external onlyOperator {
        uint256 index = productsIndex[productId_];
        require(index != 0, "Payments#setPrice: INVALID_PRODUCT_ID");
        _products[index].price = newPrice_;
    }

    /**
     * @dev Get ProductIds list.
     * Return:
     * - array of productIds
     */
    function getProducts() external view returns (string[] memory) {
        return productsList;
    }

    /**
     * @dev Get especific product details.
     * Requirements:
     * - `productId_` must be exists
     * @param productId_ productId.
     */
    function getProduct(string memory productId_) external view returns (Product[] memory) {
        uint256 index = productsIndex[productId_];
        require(index != 0, "Payments#getProduct: INVALID_PRODUCT_ID");
        Product[] memory product = new Product[](1);
        product[0] = _products[index];
        return product;
    }

    /************************|
    |          Payment       |
    |_______________________*/

    /**
     * @dev Make payment to the pool for product.
     * Requirements:
     * - `productId` must be exists
     * - `openForSale` must be true
     * @param productId deposit amount.
     */
    function payProduct(string memory productId) external override {
        uint256 index = productsIndex[productId];
        require(index != 0, "Payments#payProduct: INVALID_PRODUCT_ID");
        require(_products[index].openForSale, "Payments#payProduct: PRODUCT_UNAVAILABLE");
        _payProduct(msg.sender, productId, _products[index].price, _products[index].paymentToken);
    }

    /************************|
    |       Purchased        |
    |_______________________*/

    /**
     * @dev Return user purchases.
     * Requirements:
     *
     * - `account` must not be 0x
     * @param account address of buyer.
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
     * - `receiptId` must be exists
     * - `reimbursed` must not be 0x
     * @param receiptId_ the receiptId for refund.
     */
    function refund(uint256 receiptId_) external onlyOperator {
        require(_exists(receiptId_), "Payments#refund: RECEIPT_NOT_FOUND");
        address reimbursed = ownerOf(receiptId_);
        require(reimbursed != address(0), "Payments#refund: ZERO_ADDRESS");
        _refund(receiptId_, reimbursed);
    }

    /************************|
    |      Sweep Funds       |
    |_______________________*/

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

    function _addPaymentToken(address paymentToken_) internal virtual {
        paymentTokens[paymentToken_] = IERC20(paymentToken_);
    }

    function _payProduct(
        address account_,
        string memory productId_,
        uint256 price_,
        address paymentToken_
    ) internal virtual nonReentrant {
        IERC20 pToken = IERC20(paymentToken_);
        pToken.safeTransferFrom(account_, address(this), price_);
        uint256 receiptId = _mint(account_, productId_, price_, block.timestamp);
        userPurchases[account_].push(Purchased(productId_, receiptId, price_, block.timestamp));
        emit Paid(account_, receiptId, productId_, price_);
    }

    function _addProduct(
        string memory productId,
        address paymentToken,
        uint256 price,
        bool openForSale
    ) internal virtual {
        _products.push(Product(productId, paymentToken, price, openForSale, block.timestamp));
        productsList.push(productId);
        productsIndex[productId] = _products.length - 1;
    }

    function _refund(uint256 receiptId, address reimbursed) internal virtual nonReentrant {
        IERC20 refundToken;
        _burn(receiptId);
        Purchased[] memory purchases = userPurchases[reimbursed];
        for (uint256 i = 0; i < purchases.length; i++) {
            if (purchases[i].receiptId == receiptId) {
                uint256 index = productsIndex[purchases[i].productId];
                refundToken = IERC20(_products[index].paymentToken);
                refundToken.transfer(reimbursed, purchases[i].amount);
                _popPurchase(reimbursed, i);
                emit Refund(reimbursed, receiptId, _products[index].productId, purchases[i].amount);
                break;
            }
        }
    }

    function _popPurchase(address from, uint256 purchaseIndex) internal {
        Purchased[] storage purchases = userPurchases[from];
        if (purchaseIndex != purchases.length - 1) {
            purchases[purchaseIndex] = purchases[purchases.length - 1];
        }
        purchases.pop();
    }
}
