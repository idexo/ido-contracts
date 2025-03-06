pragma solidity ^0.8.19;  
  
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";  
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";  
import "@openzeppelin/contracts/access/Ownable.sol";  
import "@openzeppelin/contracts/utils/Strings.sol";  
import "@openzeppelin/contracts/utils/Base64.sol";  
  
/**  
 * @title ProductPaymentContract  
 * @dev Smart contract for product subscriptions with NFT receipts  
 */  
contract ProductPaymentContract is ERC721URIStorage, Ownable {  
    using Strings for uint256;  
  
    // Token-related data structures  
    uint256 private _nextTokenId;  
    IERC20 public paymentToken;  
  
    // Balance tracking  
    uint256 public lockedBalance;  
    uint256 public withdrawableBalance;  
  
    // Enum for subscription periods  
    enum SubscriptionPeriod { Monthly, Yearly, Lifetime }  
  
    // Product details structure  
    struct Product {  
        uint256 id;  
        string name;  
        string description;  
        string metadataUrl; // URL for fetching product image and additional details  
        uint256 monthlyPrice;  
        uint256 yearlyPrice;  
        uint256 lifetimePrice;  
        bool active;  
    }  
  
    // Receipt structure  
    struct Receipt {  
        uint256 productId;  
        SubscriptionPeriod period;  
        uint256 price;  
        uint256 purchaseTimestamp;  
        uint256 expiryTimestamp;  
    }  
  
    // Storage  
    mapping(uint256 => Product) public products;  
    mapping(uint256 => Receipt) public receipts;  
    uint256 public productCounter;  
  
    // Events for better traceability  
    event ProductAdded(uint256 indexed productId, string name, string metadataUrl);  
    event ProductUpdated(uint256 indexed productId, string name, string metadataUrl);  
    event ProductDeactivated(uint256 indexed productId);  
    event ProductReactivated(uint256 indexed productId);  
    event PaymentTokenUpdated(address indexed oldToken, address indexed newToken);  
    event SubscriptionPurchased(  
        address indexed buyer,   
        uint256 indexed productId,   
        uint256 receiptId,   
        SubscriptionPeriod period,   
        uint256 price,  
        uint256 expiryTimestamp  
    );  
    event WithdrawalMade(address indexed owner, uint256 amount);  
  
    // Custom errors  
    error InvalidProduct();  
    error ProductNotActive();  
    error InsufficientAllowance();  
    error TransferFailed();  
    error InvalidPrice();  
    error InvalidPeriod();  
    error NoWithdrawableBalance();  
    error InvalidToken();  
  
    /**  
     * @dev Constructor initializes the NFT token and sets the payment token  
     * @param _paymentToken Address of the ERC20 token used for payment  
     */  
    constructor(address _paymentToken) ERC721("Product Receipt", "RCPT") Ownable() {  
        if (_paymentToken == address(0)) revert InvalidToken();  
        paymentToken = IERC20(_paymentToken);  
    }  
  
    /**  
     * @dev Add a new product to the platform  
     * @param _name Product name  
     * @param _description Product description  
     * @param _metadataUrl URL for retrieving product metadata  
     * @param _monthlyPrice Price for monthly subscription  
     * @param _yearlyPrice Price for yearly subscription   
     * @param _lifetimePrice Price for lifetime access  
     */  
    function addProduct(  
        string memory _name,  
        string memory _description,  
        string memory _metadataUrl,  
        uint256 _monthlyPrice,  
        uint256 _yearlyPrice,  
        uint256 _lifetimePrice  
    ) external onlyOwner {  
        // Validate inputs  
        if (_monthlyPrice == 0 || _yearlyPrice == 0 || _lifetimePrice == 0) revert InvalidPrice();  
          
        uint256 productId = productCounter;  
        products[productId] = Product({  
            id: productId,  
            name: _name,  
            description: _description,  
            metadataUrl: _metadataUrl,  
            monthlyPrice: _monthlyPrice,  
            yearlyPrice: _yearlyPrice,  
            lifetimePrice: _lifetimePrice,  
            active: true  
        });  
          
        productCounter++;  
          
        emit ProductAdded(productId, _name, _metadataUrl);  
    }  
  
    /**  
     * @dev Update an existing product  
     * @param _productId ID of the product to update  
     * @param _name Updated product name  
     * @param _description Updated product description  
     * @param _metadataUrl Updated metadata URL  
     * @param _monthlyPrice Updated monthly price  
     * @param _yearlyPrice Updated yearly price  
     * @param _lifetimePrice Updated lifetime price  
     */  
    function updateProduct(  
        uint256 _productId,  
        string memory _name,  
        string memory _description,  
        string memory _metadataUrl,  
        uint256 _monthlyPrice,  
        uint256 _yearlyPrice,  
        uint256 _lifetimePrice  
    ) external onlyOwner {  
        if (_productId >= productCounter) revert InvalidProduct();  
        if (_monthlyPrice == 0 || _yearlyPrice == 0 || _lifetimePrice == 0) revert InvalidPrice();  
          
        Product storage product = products[_productId];  
          
        product.name = _name;  
        product.description = _description;  
        product.metadataUrl = _metadataUrl;  
        product.monthlyPrice = _monthlyPrice;  
        product.yearlyPrice = _yearlyPrice;  
        product.lifetimePrice = _lifetimePrice;  
          
        emit ProductUpdated(_productId, _name, _metadataUrl);  
    }  
  
    /**  
     * @dev Deactivate a product to discontinue it  
     * @param _productId ID of the product to deactivate  
     */  
    function deactivateProduct(uint256 _productId) external onlyOwner {  
        if (_productId >= productCounter) revert InvalidProduct();  
          
        products[_productId].active = false;  
          
        emit ProductDeactivated(_productId);  
    }  
  
    /**  
     * @dev Reactivate a previously deactivated product  
     * @param _productId ID of the product to reactivate  
     */  
    function reactivateProduct(uint256 _productId) external onlyOwner {  
        if (_productId >= productCounter) revert InvalidProduct();  
          
        products[_productId].active = true;  
          
        emit ProductReactivated(_productId);  
    }  
  
    /**  
     * @dev Update the payment token  
     * @param _newPaymentToken Address of the new ERC20 token  
     */  
    function updatePaymentToken(address _newPaymentToken) external onlyOwner {  
        if (_newPaymentToken == address(0)) revert InvalidToken();  
          
        address oldToken = address(paymentToken);  
        paymentToken = IERC20(_newPaymentToken);  
          
        emit PaymentTokenUpdated(oldToken, _newPaymentToken);  
    }  
  
    /**  
     * @dev Purchase a subscription for a product  
     * @param _productId ID of the product to purchase  
     * @param _period Subscription period (0=Monthly, 1=Yearly, 2=Lifetime)  
     */  
    function purchaseSubscription(uint256 _productId, uint8 _period) external {  
        // Validate inputs  
        if (_productId >= productCounter) revert InvalidProduct();  
          
        Product memory product = products[_productId];  
        if (!product.active) revert ProductNotActive();  
          
        if (_period > uint8(SubscriptionPeriod.Lifetime)) revert InvalidPeriod();  
        SubscriptionPeriod period = SubscriptionPeriod(_period);  
          
        // Determine price and expiry based on period  
        uint256 price;  
        uint256 expiryTimestamp;  
          
        if (period == SubscriptionPeriod.Monthly) {  
            price = product.monthlyPrice;  
            expiryTimestamp = block.timestamp + 30 days;  
        } else if (period == SubscriptionPeriod.Yearly) {  
            price = product.yearlyPrice;  
            expiryTimestamp = block.timestamp + 365 days;  
        } else {  
            price = product.lifetimePrice;  
            expiryTimestamp = type(uint256).max; // Never expires  
        }  
          
        // Handle payment  
        if (paymentToken.allowance(msg.sender, address(this)) < price) revert InsufficientAllowance();  
          
        bool success = paymentToken.transferFrom(msg.sender, address(this), price);  
        if (!success) revert TransferFailed();  
          
        // Update balances (50% locked, 50% withdrawable)  
        uint256 halfPrice = price / 2;  
        lockedBalance += halfPrice;  
        withdrawableBalance += price - halfPrice; // Handle odd numbers correctly  
          
        // Create receipt NFT  
        uint256 tokenId = _nextTokenId++;  
          
        // Store receipt data  
        receipts[tokenId] = Receipt({  
            productId: _productId,  
            period: period,  
            price: price,  
            purchaseTimestamp: block.timestamp,  
            expiryTimestamp: expiryTimestamp  
        });  
          
        // Mint receipt NFT  
        _mint(msg.sender, tokenId);  
        _setTokenURI(tokenId, _generateReceiptURI(tokenId));  
          
        emit SubscriptionPurchased(  
            msg.sender,   
            _productId,   
            tokenId,   
            period,   
            price,  
            expiryTimestamp  
        );  
    }  
  
    /**  
     * @dev Withdraw available balance  
     * @param _amount Amount to withdraw  
     */  
    function withdraw(uint256 _amount) external onlyOwner {  
        if (_amount == 0 || _amount > withdrawableBalance) revert NoWithdrawableBalance();  
          
        withdrawableBalance -= _amount;  
          
        bool success = paymentToken.transfer(owner(), _amount);  
        if (!success) revert TransferFailed();  
          
        emit WithdrawalMade(owner(), _amount);  
    }  
  
    /**  
     * @dev Generate JSON metadata URI for the receipt NFT  
     * @param _tokenId Receipt token ID  
     * @return string URI with embedded metadata  
     */  
    function _generateReceiptURI(uint256 _tokenId) internal view returns (string memory) {  
        Receipt memory receipt = receipts[_tokenId];  
        Product memory product = products[receipt.productId];  
          
        string memory periodString;  
        if (receipt.period == SubscriptionPeriod.Monthly) {  
            periodString = "Monthly";  
        } else if (receipt.period == SubscriptionPeriod.Yearly) {  
            periodString = "Yearly";  
        } else {  
            periodString = "Lifetime";  
        }  
          
        bytes memory json = abi.encodePacked(  
            '{',  
                '"name": "Receipt #', _tokenId.toString(), ' - ', product.name, '",',  
                '"description": "Subscription receipt for ', product.name, '",',  
                '"external_url": "', product.metadataUrl, '",',  
                '"attributes": [',  
                    '{"trait_type": "Product ID", "value": "', receipt.productId.toString(), '"},',  
                    '{"trait_type": "Product Name", "value": "', product.name, '"},',  
                    '{"trait_type": "Subscription", "value": "', periodString, '"},',  
                    '{"trait_type": "Purchase Date", "value": "', receipt.purchaseTimestamp.toString(), '"},',  
                    '{"trait_type": "Expiry Date", "value": "', receipt.expiryTimestamp.toString(), '"},',  
                    '{"trait_type": "Price", "value": "', receipt.price.toString(), '"}'  
                ']',  
            '}'  
        );  
          
        return string(  
            abi.encodePacked(  
                "data:application/json;base64,",  
                Base64.encode(json)  
            )  
        );  
    }  
  
    /**  
     * @dev Get all active products  
     * @return Array of active Product structs  
     */  
    function getActiveProducts() external view returns (Product[] memory) {  
        uint256 activeCount = 0;  
          
        // Count active products  
        for (uint256 i = 0; i < productCounter; i++) {  
            if (products[i].active) {  
                activeCount++;  
            }  
        }  
          
        // Populate array with active products  
        Product[] memory activeProducts = new Product[](activeCount);  
        uint256 currentIndex = 0;  
          
        for (uint256 i = 0; i < productCounter; i++) {  
            if (products[i].active) {  
                activeProducts[currentIndex] = products[i];  
                currentIndex++;  
            }  
        }  
          
        return activeProducts;  
    }  
  
    /**  
     * @dev Get all receipts for a specific user  
     * @param _user Address of the user  
     * @return Array of token IDs owned by the user  
     */  
    function getUserReceipts(address _user) external view returns (uint256[] memory) {  
        uint256 balance = balanceOf(_user);  
        uint256[] memory tokenIds = new uint256[](balance);  
          
        for (uint256 i = 0; i < balance; i++) {  
            tokenIds[i] = tokenOfOwnerByIndex(_user, i);  
        }  
          
        return tokenIds;  
    }  
      
    /**  
     * @dev Check if a receipt is valid (not expired)  
     * @param _tokenId Receipt token ID  
     * @return bool True if the receipt is still valid  
     */  
    function isValidReceipt(uint256 _tokenId) external view returns (bool) {  
        if (_tokenId >= _nextTokenId) return false;  
          
        Receipt memory receipt = receipts[_tokenId];  
        return block.timestamp <= receipt.expiryTimestamp;  
    }  
      
    /**  
     * @dev Get detailed receipt information  
     * @param _tokenId Receipt token ID  
     * @return productId Product ID  
     * @return period Subscription period (0=Monthly, 1=Yearly, 2=Lifetime)  
     * @return price Price paid  
     * @return purchaseTimestamp When the purchase was made  
     * @return expiryTimestamp When the subscription expires  
     * @return productName Name of the product  
     * @return isValid Whether the receipt is still valid  
     */  
    function getReceiptDetails(uint256 _tokenId) external view   
    returns (  
        uint256 productId,  
        SubscriptionPeriod period,  
        uint256 price,  
        uint256 purchaseTimestamp,  
        uint256 expiryTimestamp,  
        string memory productName,  
        bool isValid  
    ) {  
        Receipt memory receipt = receipts[_tokenId];  
        Product memory product = products[receipt.productId];  
          
        return (  
            receipt.productId,  
            receipt.period,  
            receipt.price,  
            receipt.purchaseTimestamp,  
            receipt.expiryTimestamp,  
            product.name,  
            block.timestamp <= receipt.expiryTimestamp  
        );  
    }  
      
    /**  
     * @dev Function to handle ERC721 enumeration  
     * @param _owner Address to query  
     * @param _index Index of the token in the owner's collection  
     * @return uint256 Token ID at the given index  
     */  
    function tokenOfOwnerByIndex(address _owner, uint256 _index) public view returns (uint256) {  
        require(_index < balanceOf(_owner), "Index out of bounds");  
          
        uint256 count = 0;  
        for (uint256 i = 0; i < _nextTokenId; i++) {  
            if (_exists(i) && ownerOf(i) == _owner) {  
                if (count == _index) {  
                    return i;  
                }  
                count++;  
            }  
        }  
          
        revert("Token not found");  
    }  
}  