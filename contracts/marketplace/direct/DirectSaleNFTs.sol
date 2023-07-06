// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/metatx/MinimalForwarder.sol";

contract DirectSaleNFTs is ERC2771Context, Ownable2Step {
    using SafeERC20 for IERC20;

    // ERC20 token
    address public purchaseToken;

    //last sale id - start from 1
    uint256 public saleIds;

    struct NFTSaleInfo {
        address nftContractAddress;
        uint256 tokenid;
        address seller;
        uint256 price;
        bool isOpenForSale;
    }

    //sale id => sale info
    mapping(uint256 => NFTSaleInfo) public salesById;

    // nft address => nft id => nft sale id structure for retrieving saleId by ntfTokenId
    mapping(address => mapping(uint256 => uint256)) public nftIdSaleId;

    // nft address => nft id => nft sale info structure
    mapping(address => mapping(uint256 => NFTSaleInfo)) public nftSales;

    event SaleOpened(address indexed nftAddress, uint256 indexed tokenID);
    event SaleClosed(address indexed nftAddress, uint256 indexed tokenID);
    event PriceSet(address indexed nftAddress, uint256 indexed tokenID, uint256 price);
    event Purchased(address indexed nftAddress, uint256 indexed tokenID, address seller, address buyer);
    event FalseSeller(address seller, address falseSeller);
    event Swept(address token, address to);

    constructor(address _purchaseToken, address _trustedForwarder) ERC2771Context(_trustedForwarder) {
        require(_purchaseToken != address(0), "ADDRESS_ZERO");

        purchaseToken = _purchaseToken;
    }

    function currentOwner(address _nft, uint256 _tokenID) internal virtual view returns (address) {
        return IERC721(_nft).ownerOf(_tokenID);
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
    ) external {
        require(_msgSender() == currentOwner(_nft, _tokenID), "CALLER_NOT_NFT_OWNER");

        saleIds++;
        NFTSaleInfo storage nftSale = salesById[saleIds];

        nftSale.nftContractAddress = _nft;
        nftSale.tokenid = _tokenID;
        nftSale.seller = _msgSender();
        nftSale.price = _price;
        nftSale.isOpenForSale = true;


        _setPrice(_nft, _tokenID, _price);
        nftSales[_nft][_tokenID].seller = _msgSender();
        nftSales[_nft][_tokenID].isOpenForSale = true;

        emit SaleOpened(_nft, _tokenID);
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
    ) public {
        uint256 nftSaleId = nftIdSaleId[_nft][_tokenID];
        NFTSaleInfo storage nftSale = salesById[nftSaleId];
        require(nftSale.isOpenForSale, "SALE_CLOSED");
        require(_price != 0, "INVALID_PRICE");
        require(_msgSender() == IERC721(_nft).ownerOf(_tokenID), "CALLER_NOT_NFT_OWNER_OR_TOKEN_INVALID");
        require(_msgSender() == nftSales[_nft][_tokenID].seller, "OWNERSHIP_CHANGED");
        nftSale.price = _price;

        _setPrice(_nft, _tokenID, _price);
        emit PriceSet(_nft, _tokenID, _price);
    }

    function _setPrice(
        address _nft,
        uint256 _tokenID,
        uint256 _price
    ) private {
        nftSales[_nft][_tokenID].price = _price;

        emit PriceSet(_nft, _tokenID, _price);
    }

    /**
     * @dev Close `_tokenID` for sale
     * Accessible by only nft owner
     * `_tokenID` must exist
     */
    function closeForSale(uint256 _saleId, address _nft, uint256 _tokenID) external {
        NFTSaleInfo storage nftSale = salesById[_saleId];
        require(_msgSender() == currentOwner(_nft, _tokenID), "CALLER_NOT_NFT_OWNER_OR_TOKEN_INVALID");
        require(nftSale.isOpenForSale, "SALE_NOT_OPEN");


        nftSales[_nft][_tokenID].isOpenForSale = false;

        emit SaleClosed(_nft, _tokenID);
    }

    /**
     * @dev Purchase `_tokenID`
     * Collect royalty fee and send to royalties collector address
     * `_tokenID` must exist
     * `_tokenID` must be open for sale
     */
    function purchase(address _nft, uint256 _tokenID) external {
        uint256 nftSaleId = nftIdSaleId[_nft][_tokenID];
        NFTSaleInfo memory nftSale = salesById[nftSaleId];
        address nftOwner = currentOwner(_nft, _tokenID);
        require(nftSales[_nft][_tokenID].isOpenForSale, "NFT_SALE_CLOSED");
        require(nftOwner != address(0), "INVALID_NFT");
        require(nftOwner != _msgSender(), "SELF_PURCHASE");



        if ((nftOwner != nftSales[_nft][_tokenID].seller)) {
            nftSales[_nft][_tokenID].isOpenForSale = false;
            nftSale.isOpenForSale = false;
            emit FalseSeller(nftOwner, nftSales[_nft][_tokenID].seller);
        } else {
            _purchase(_nft, nftOwner, _msgSender(), _tokenID);
        }
    }

    function _purchase(
        address _nft,
        address _tokenOwner,
        address _buyer,
        uint256 _tokenID
    ) internal virtual {
        uint256 nftSaleId = nftIdSaleId[_nft][_tokenID];

        NFTSaleInfo memory nftSale = salesById[nftSaleId];
        nftSale.isOpenForSale = false;
        
        nftSales[_nft][_tokenID].isOpenForSale = false;

        
        IERC20(purchaseToken).safeTransferFrom(_buyer, _tokenOwner, nftSales[_nft][_tokenID].price);
        IERC721(_nft).safeTransferFrom(_tokenOwner, _buyer, _tokenID);
        

        emit Purchased(_nft, _tokenID, _tokenOwner, _buyer);
    }

    /**
     * @dev Transfer `_token` all amount to `_to`
     * Accessible by only owner
     */
    function sweep(address _token, address _to) external onlyOwner {
        require(_token != address(0), "INVALID_ADDRESS");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_to, amount);

        emit Swept(_token, _to);
    }

    /// @notice Overrides _msgSender() function from Context.sol
    /// @return address The current execution context's sender address
    function _msgSender() internal view override(Context, ERC2771Context) returns (address){
        return ERC2771Context._msgSender();
    }

    /// @notice Overrides _msgData() function from Context.sol
    /// @return address The current execution context's data
    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata){
        return ERC2771Context._msgData();
    }
}
