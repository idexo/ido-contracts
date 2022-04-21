// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract DirectSaleNFTs is Ownable, Pausable {
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

    event LogOpenForSale(uint256 indexed tokenID);
    event LogCloseForSale(uint256 indexed tokenID);
    event LogPriceSet(uint256 indexed tokenID, uint256 price);
    event LogPurchase(uint256 indexed tokenID, address seller, address buyer);
    event LogSweep(address token, address to);

    constructor(address _purchaseToken, uint256 _saleStartTime) {
        if (_saleStartTime == 0) _saleStartTime = block.timestamp;
        require(_purchaseToken != address(0), "DirectNFTs#constructor: ADDRESS_ZERO");
        require(_saleStartTime >= block.timestamp, "DirectNFTs#constructor: INVALID_SALE_START");

        purchaseToken = _purchaseToken;
        saleStartTime = _saleStartTime;
    }

    modifier saleIsOpen() {
        require(!paused() || saleStartTime <= block.timestamp, "DirectNFTs#saleIsOpen: SALE_NOT_OPEN");
        _;
    }

    /**
     * @dev Set `saleStartTime`
     * Only owner can call
     * `_saleStartTime` must be greater than current timestamp
     */
    function setSaleStartTime(uint256 _saleStartTime) external onlyOwner {
        require(saleStartTime > block.timestamp, "DirectNFTs#setSaleStartTime: SALE_STARTED");
        require(_saleStartTime > block.timestamp, "DirectNFTs#setSaleStartTime: INVALID_SALE_START");

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
        require(msg.sender == IERC721(_nft).ownerOf(_tokenID), "DirectNFTs#openForSale: CALLER_NOT_NFT_OWNER");

        NFTSaleInfo storage nftSale = nftSales[_nft][_tokenID];

        _setPrice(_nft, _tokenID, _price);
        nftSale.seller = msg.sender;
        nftSale.isOpenForSale = true;

        emit LogOpenForSale(_tokenID);
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
        require(_price != 0, "DirectNFTs#setPrice: INVALID_PRICE");
        require(msg.sender == IERC721(_nft).ownerOf(_tokenID), "DirectNFTs#setPrice: CALLER_NOT_NFT_OWNER_OR_TOKEN_INVALID");

        NFTSaleInfo memory nftSale = nftSales[_nft][_tokenID];
        require(msg.sender == nftSale.seller, "DirectNFTs#setPrice: OWNERSHIP_CHANGED");

        _setPrice(_nft, _tokenID, _price);
    }

    function _setPrice(
        address _nft,
        uint256 _tokenID,
        uint256 _price
    ) private {
        NFTSaleInfo storage nftSale = nftSales[_nft][_tokenID];
        nftSale.price = _price;

        emit LogPriceSet(_tokenID, _price);
    }

    /**
     * @dev Close `_tokenID` for sale
     * Accessible by only nft owner
     * `_tokenID` must exist
     */
    function closeForSale(address _nft, uint256 _tokenID) external {
        require(msg.sender == IERC721(_nft).ownerOf(_tokenID), "DirectNFTs#closeForSale: CALLER_NOT_NFT_OWNER_OR_TOKEN_INVALID");

        nftSales[_nft][_tokenID].isOpenForSale = false;

        emit LogCloseForSale(_tokenID);
    }

    /**
     * @dev Purchase `_tokenID`
     * Collect royalty fee and send to royalties collector address
     * `_tokenID` must exist
     * `_tokenID` must be open for sale
     */
    function purchase(address _nft, uint256 _tokenID) external saleIsOpen {
        NFTSaleInfo memory nftSale = nftSales[_nft][_tokenID];
        address nftOwner = IERC721(_nft).ownerOf(_tokenID);
        require(nftSale.isOpenForSale, "DirectNFTs#purchase: NFT_SALE_CLOSED");
        require(nftOwner != address(0), "DirectNFTs#purchase: INVALID_NFT");
        require(nftOwner != msg.sender, "DirectNFTs#purchase: SELF_PURCHASE");
        require(nftOwner == nftSale.seller, "DirectNFTs#purchase: OWNERSHIP_CHANGED");

        _purchase(_nft, nftOwner, msg.sender, _tokenID);
    }

    function _purchase(
        address _nft,
        address _tokenOwner,
        address _buyer,
        uint256 _tokenID
    ) private {
        NFTSaleInfo storage nftSale = nftSales[_nft][_tokenID];

        require(nftSale.price != 0, "DirectNFTs#_purchase: INVALID_PRICE");

        IERC20(purchaseToken).safeTransferFrom(_buyer, _tokenOwner, nftSale.price);
        IERC721(_nft).safeTransferFrom(_tokenOwner, _buyer, _tokenID);
        nftSale.isOpenForSale = false;

        emit LogPurchase(_tokenID, _tokenOwner, _buyer);
    }

    /**
     * @dev Transfer `_token` all amount to `_to`
     * Accessible by only owner
     */
    function sweep(address _token, address _to) external onlyOwner {
        require(_token != address(0), "DirectNFTs#sweep: INVALID_ADDRESS");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_to, amount);

        emit LogSweep(_token, _to);
    }
}
