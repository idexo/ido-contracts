// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../lib/Operatorable.sol";

contract PaymentNew is ReentrancyGuard, Operatorable {
    using SafeERC20 for IERC20;

    // Mapping of payment tokens.
    mapping(address => IERC20) public paymentTokens;

    // Timestamp when contract was deployed to mainnet.
    uint256 public deployedAt;

    struct Product {
        string productId;
        string productName;
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
    Product[] public productsList;

    // Products index
    mapping(string => uint256) productsIndex;

    // User purchases
    mapping(address => Purchased[]) public purchasedProducts;

    // event Purchased(address indexed account, string productName, uint256 price);

    event Swept(address indexed operator, address token, address indexed to, uint256 amount);

    constructor(address paymentToken_) {
        paymentTokens[paymentToken_] = IERC20(paymentToken_);
        productsList.push(
            Product({ productId: "", productName: "", paymentToken: address(0), price: 0, openForSale: false, insertedAt: block.timestamp })
        );
        deployedAt = block.timestamp;
    }

    /************************|
    |        Purchase        |
    |_______________________*/

    /**
     * @dev Payment.
     * Requirements:
     *
     * - `price` must not be zero
     * - `productName`
     * @param productId of product
     */
    function purchaseProduct(string memory productId) external {
        uint256 index = productsIndex[productId];
        require(index != 0, "INVALID_PRODUCT_ID");

        address paymentToken = productsList[index].paymentToken;
        uint256 price = productsList[index].price;

        // require(price <= paymentTokens[paymentToken].balanceOf(msg.sender), "Payment#purchase: INSUFFICIENT_BALANCE");

        _purchase(msg.sender, index);
    }

    /*************************|
    |         Product         |
    |________________________*/

    /**
     * @dev Deposit reward to the pool.
     * Requirements:
     *
     * - `amount` must not be zero
     * @param productId_ deposit amount.
     * @param productName_ deposit amount.
     * @param paymentToken_ deposit amount.
     * @param price_ reward token address
     * @param openForSale_ reward token address
     */
    function addProduct(
        string memory productId_,
        string memory productName_,
        address paymentToken_,
        uint256 price_,
        bool openForSale_
    ) external onlyOperator {
        require(price_ > 0, "Payment#addProduct: ZERO_PRICE");
        _addProduct(productId_, productName_, paymentToken_, price_, openForSale_);
    }

    function getProducts() external view returns (Product[] memory) {
        return productsList;
    }

    function getProduct(string memory productId) external view returns (Product memory product) {
        uint256 index = productsIndex[productId];

        if (index == 0) return product;
        return productsList[index];
    }

    function setOpenForSale(string memory productId_, bool openForSale_) external onlyOperator {
        uint256 index = productsIndex[productId_];

        if (index == 0) return;
        productsList[index].openForSale = openForSale_;
    }

    function setPaymentToken(string memory productId_, address paymentToken_) external onlyOperator {
        uint256 index = productsIndex[productId_];

        if (index == 0) return;
        productsList[index].paymentToken = paymentToken_;
    }

    function setPrice(string memory productId_, uint256 price_) external onlyOperator {
        uint256 index = productsIndex[productId_];

        if (index == 0) return;
        productsList[index].price = price_;
    }

    function getPrice(string memory productId_) external view returns (uint256) {
        uint256 index = productsIndex[productId_];

        if (index == 0) return 0;
        return productsList[index].price;
    }

    /*************************|
    |      Check Balance      |
    |________________________*/

    function checkPaymentBalance(address paymentToken_) external view returns (uint256) {
        return paymentTokens[paymentToken_].balanceOf(msg.sender);
    }

    /*************************|
    |       Manager Funds     |
    |________________________*/

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
    |   Internal Functions     |
    |________________________*/

    /**
     * @dev Deposit reward to the pool.
     * @param productName address who deposits to the pool.
     * @param price deposit aproductName_  price_
     * @param productId deposit aproductName_  price_
     * @param paymentToken deposit aproductName_  price_
     * @param openForSale deposit aproductName_  price_
     */
    function _addProduct(
        string memory productId,
        string memory productName,
        address paymentToken,
        uint256 price,
        bool openForSale
    ) internal virtual {
        productsList.push(
            Product({
                productId: productId,
                productName: productName,
                paymentToken: paymentToken,
                price: price,
                openForSale: openForSale,
                insertedAt: block.timestamp
            })
        );
        productsIndex[productId] = productsList.length - 1;
    }

    /**
     * @dev Deposit stake to the pool.
     * @param account address of recipient.
     * @param productIndex deposit amount.
     */
    function _purchase(address account, uint256 productIndex) internal virtual nonReentrant {
        uint256 purchasedAt = block.timestamp;
        IERC20 paymentToken = IERC20(productsList[productIndex].paymentToken);
        uint256 price = productsList[productIndex].price;

        paymentToken.transferFrom(account, address(this), price);
        // purchasedProducts[account].push();

        // emit Purchased(account, productName, price);
    }

    /**
     * @dev Add new payment token.
     * @param paymentToken_ payment token address.
     */
    function _addPaymentToken(address paymentToken_) internal virtual {
        paymentTokens[paymentToken_] = IERC20(paymentToken_);
    }
}
