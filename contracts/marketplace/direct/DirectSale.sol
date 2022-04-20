// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

// import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "./Error.sol";
import "./RoyaltyNFT.sol";

contract DirectSale is Ownable, Pausable {
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

  constructor(
    address _purchaseToken,
    uint256 _saleStartTime
  ) {
    if (_purchaseToken == address(0)) revert InvalidAddress();
    if (_saleStartTime <= block.timestamp) revert InvalidSaleStartTime();
    purchaseToken = _purchaseToken;
    saleStartTime = _saleStartTime;
  }

  modifier saleIsOpen() {
    if (paused() || block.timestamp < saleStartTime) revert SaleNotOpen();
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
    if (msg.sender != RoyaltyNFT(_nft).ownerOf(_tokenID)) revert CallerNotNFTOwnerOrTokenInvalid();
    NFTSaleInfo memory nftSale = nftSales[_nft][_tokenID];
    if (msg.sender != nftSale.seller) revert OwnershipChanged();
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
  function closeForSale(
    address _nft,
    uint256 _tokenID
  ) external {
    if (msg.sender != RoyaltyNFT(_nft).ownerOf(_tokenID)) revert CallerNotNFTOwnerOrTokenInvalid();
    nftSales[_nft][_tokenID].isOpenForSale = false;

    emit LogCloseForSale(_tokenID);
  }

  /**
    * @dev Purchase `_tokenID`
    * Collect royalty fee and send to royalties collector address
    * `_tokenID` must exist
    * `_tokenID` must be open for sale
    */
  function purchase(
    address _nft,
    uint256 _tokenID
  ) external saleIsOpen {
    NFTSaleInfo memory nftSale = nftSales[_nft][_tokenID];

    address nftOwner = RoyaltyNFT(_nft).ownerOf(_tokenID);
    if (nftOwner == address(0)) revert InvalidNFTId();
    if (nftOwner == msg.sender) revert SelfPurchase();
    if (nftOwner != nftSale.seller) revert OwnershipChanged();

    bool isOpenForSale = nftSale.isOpenForSale;
    if (!isOpenForSale) revert NFTClosedForSale();

    _purchase(_nft, nftOwner, msg.sender, _tokenID);
  }

  function _purchase(
    address _nft,
    address _tokenOwner,
    address _buyer,
    uint256 _tokenID
  ) private {
    NFTSaleInfo storage nftSale = nftSales[_nft][_tokenID];
    uint256 price = nftSale.price;
    if (price == 0) revert InvalidPrice();

    uint256 royaltyFee = price * RoyaltyNFT(_nft).royaltiesFeeBP() / 10000;
    IERC20(purchaseToken).safeTransferFrom(_buyer, RoyaltyNFT(_nft).royaltiesCollector(), royaltyFee);
    IERC20(purchaseToken).safeTransferFrom(_buyer, _tokenOwner, price - royaltyFee);
    RoyaltyNFT(_nft).safeTransferFrom(_tokenOwner, _buyer, _tokenID);
    nftSale.isOpenForSale = false;

    emit LogPurchase(_tokenID, _tokenOwner, _buyer);
  }

  /**
   * @dev Transfer `_token` all amount to `_to`
   * Accessible by only owner
   */
  function sweep(
    address _token,
    address _to
  ) external onlyOwner {
    if (_token == address(0)) revert InvalidAddress();
    uint256 amount = IERC20(_token).balanceOf(address(this));
    IERC20(_token).safeTransfer(_to, amount);

    emit LogSweep(_token, _to);
  }
}
