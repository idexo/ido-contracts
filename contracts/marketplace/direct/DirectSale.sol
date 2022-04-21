// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./RoyaltyNFT.sol";

contract DirectSale is Ownable {
    using SafeERC20 for IERC20;

    // ERC20 token
    address public purchaseToken;
    // Public sale start date
    uint256 public saleStartTime;

    struct NFTSaleInfo {
        address seller;
        uint256 price;
        bool isOpenForSale;
    }

    // nft address => nft id => nft sale info structure
    mapping(address => mapping(uint256 => NFTSaleInfo)) public nftSales;

    event SaleOpened(uint256 indexed tokenID);
    event SaleClosed(uint256 indexed tokenID);
    event PriceSet(uint256 indexed tokenID, uint256 price);
    event Purchased(uint256 indexed tokenID, address seller, address buyer);
    event FalseSeller(address seller, address falseSeller);
    event Swept(address token, address to);

    constructor(address _purchaseToken, uint256 _saleStartTime) {
        if (_purchaseToken == address(0)) revert InvalidAddress();
        if (_saleStartTime <= block.timestamp) revert InvalidSaleStartTime();
        purchaseToken = _purchaseToken;
        saleStartTime = _saleStartTime;
    }

    modifier saleIsOpen() {
        if (block.timestamp < saleStartTime) revert SaleNotOpen();
        _;
    }

    /**
     * @dev Set `saleStartTime`
     * Only owner can call
     * `_saleStartTime` must be greater than current timestamp
     */
    function setSaleStartTime(uint256 _saleStartTime) external onlyOwner {
        if (saleStartTime <= block.timestamp) revert SaleStarted();
        if (_saleStartTime <= block.timestamp) revert InvalidSaleStartTime();
        saleStartTime = _saleStartTime;
    }

    /**
     * @dev Open `_tokenID` for sale
     * Accessible by only nft owner
     * `_tokenID` must exist
     * `_price` must not be zero
     */
    function openForSale(
        address _nft,
        uint256 _tokenID,
        uint256 _price
    ) external saleIsOpen {
        if (msg.sender != RoyaltyNFT(_nft).ownerOf(_tokenID)) revert CallerNotNFTOwner();

        _setPrice(_nft, _tokenID, _price);
        nftSales[_nft][_tokenID].seller = msg.sender;
        nftSales[_nft][_tokenID].isOpenForSale = true;

        emit SaleOpened(_tokenID);
    }

    /**
     * @dev Set nft price
     * Accessible by only nft owner
     * `_tokenID` must exist
     * `_price` must not be zero
     */
    function setPrice(
        address _nft,
        uint256 _tokenID,
        uint256 _price
    ) public saleIsOpen {
        if (msg.sender != RoyaltyNFT(_nft).ownerOf(_tokenID)) revert CallerNotNFTOwnerOrTokenInvalid();
        if (msg.sender != nftSales[_nft][_tokenID].seller) revert OwnershipChanged();
        _setPrice(_nft, _tokenID, _price);
    }

    function _setPrice(
        address _nft,
        uint256 _tokenID,
        uint256 _price
    ) private {
        nftSales[_nft][_tokenID].price = _price;

        emit PriceSet(_tokenID, _price);
    }

    /**
     * @dev Close `_tokenID` for sale
     * Accessible by only nft owner
     * `_tokenID` must exist
     */
    function closeForSale(address _nft, uint256 _tokenID) external {
        if (msg.sender != RoyaltyNFT(_nft).ownerOf(_tokenID)) revert CallerNotNFTOwnerOrTokenInvalid();
        nftSales[_nft][_tokenID].isOpenForSale = false;

        emit SaleClosed(_tokenID);
    }

    /**
     * @dev Purchase `_tokenID`
     * Collect royalty fee and send to royalties collector address
     * `_tokenID` must exist
     * `_tokenID` must be open for sale
     */
    function purchase(address _nft, uint256 _tokenID) external saleIsOpen {
        address nftOwner = RoyaltyNFT(_nft).ownerOf(_tokenID);
        if (nftOwner == address(0)) revert InvalidNFTId();
        if (nftOwner == msg.sender) revert SelfPurchase();
        if (nftOwner != nftSales[_nft][_tokenID].seller) revert OwnershipChanged();

        bool isOpenForSale = nftSales[_nft][_tokenID].isOpenForSale;
        if (!isOpenForSale) revert NFTClosedForSale();

        _purchase(_nft, nftOwner, msg.sender, _tokenID);
    }

    function _purchase(
        address _nft,
        address _tokenOwner,
        address _buyer,
        uint256 _tokenID
    ) private {
        uint256 price = nftSales[_nft][_tokenID].price;
        if (price == 0) revert InvalidPrice();

        uint256 royaltyFee = (price * RoyaltyNFT(_nft).royaltiesFeeBP()) / 10000;
        IERC20(purchaseToken).safeTransferFrom(_buyer, RoyaltyNFT(_nft).royaltiesCollector(), royaltyFee);
        IERC20(purchaseToken).safeTransferFrom(_buyer, _tokenOwner, price - royaltyFee);
        RoyaltyNFT(_nft).safeTransferFrom(_tokenOwner, _buyer, _tokenID);
        nftSales[_nft][_tokenID].isOpenForSale = false;

        emit Purchased(_tokenID, _tokenOwner, _buyer);
    }

    /**
     * @dev Transfer `_token` all amount to `_to`
     * Accessible by only owner
     */
    function sweep(address _token, address _to) external onlyOwner {
        if (_token == address(0)) revert InvalidAddress();
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_to, amount);

        emit Swept(_token, _to);
    }
}
