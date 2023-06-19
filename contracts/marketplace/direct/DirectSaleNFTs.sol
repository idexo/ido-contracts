// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract DirectSaleNFTs is ERC2771Context, Ownable2Step {
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

    constructor(address _purchaseToken, uint256 _saleStartTime, address _trustedForwarder) ERC2771Context(_trustedForwarder) {
        if (_saleStartTime == 0) _saleStartTime = block.timestamp;
        require(_purchaseToken != address(0), "ADDRESS_ZERO");
        require(_saleStartTime >= block.timestamp, "INVALID_SALE_START");

        purchaseToken = _purchaseToken;
        saleStartTime = _saleStartTime;
    }

    modifier saleIsOpen() {
        require(saleStartTime <= block.timestamp, "SALE_NOT_OPEN");
        _;
    }

    /**
     * @dev Set `saleStartTime`
     * Only owner can call
     * `_saleStartTime` must be greater than current timestamp
     */
    function setSaleStartTime(uint256 _saleStartTime) external onlyOwner {
        require(saleStartTime > block.timestamp, "SALE_STARTED");
        require(_saleStartTime > block.timestamp, "INVALID_SALE_START");

        saleStartTime = _saleStartTime;
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
    ) external saleIsOpen {
        require(msg.sender == currentOwner(_nft, _tokenID), "CALLER_NOT_NFT_OWNER");

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
        require(_price != 0, "INVALID_PRICE");
        require(msg.sender == IERC721(_nft).ownerOf(_tokenID), "CALLER_NOT_NFT_OWNER_OR_TOKEN_INVALID");
        require(msg.sender == nftSales[_nft][_tokenID].seller, "OWNERSHIP_CHANGED");

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
        require(msg.sender == currentOwner(_nft, _tokenID), "CALLER_NOT_NFT_OWNER_OR_TOKEN_INVALID");

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
        address nftOwner = currentOwner(_nft, _tokenID);
        require(nftSales[_nft][_tokenID].isOpenForSale, "NFT_SALE_CLOSED");
        require(nftOwner != address(0), "INVALID_NFT");
        require(nftOwner != msg.sender, "SELF_PURCHASE");

        if ((nftOwner != nftSales[_nft][_tokenID].seller)) {
            nftSales[_nft][_tokenID].isOpenForSale = false;
            emit FalseSeller(nftOwner, nftSales[_nft][_tokenID].seller);
        } else {
            _purchase(_nft, nftOwner, msg.sender, _tokenID);
        }
    }

    function _purchase(
        address _nft,
        address _tokenOwner,
        address _buyer,
        uint256 _tokenID
    ) internal virtual {
        require(nftSales[_nft][_tokenID].price != 0, "INVALID_PRICE");
        
        nftSales[_nft][_tokenID].isOpenForSale = false;

        
        IERC20(purchaseToken).safeTransferFrom(_buyer, _tokenOwner, nftSales[_nft][_tokenID].price);
        IERC721(_nft).safeTransferFrom(_tokenOwner, _buyer, _tokenID);
        

        emit Purchased(_tokenID, _tokenOwner, _buyer);
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
