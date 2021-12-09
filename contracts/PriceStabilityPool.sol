// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./lib/Operatorable.sol";
import "./lib/Whitelist.sol";

/**
 * @dev Draft version of Idexo transaction price stability pool
 */
contract PriceStabilityPool is ERC721Enumerable, Operatorable, Whitelist, ReentrancyGuard {
  using SafeERC20 for IERC20;

  // WIDO token address
  IERC20 wido;
  // Coupon NFT structure
  struct CouponInfo {
    uint256 duration;
  }
  // Last stake NFT id, start from 1
  uint256 public tokenIds;
  // Entrance fee for whitelist in WIDO
  uint256 public entranceFee;
  // One time coupon fee
  uint256 public fee0;
  // 1 month coupon fee
  uint256 public fee1;
  // 3 month coupon fee
  uint256 public fee2;

  // Coupon id => info
  mapping(uint256 => CouponInfo) public coupons;

  constructor(
    string memory _name,
    string memory _symbol,
    IERC20 _wido,
    uint256 _entranceFee
  ) ERC721(_name, _symbol) {
    require(address(_wido) != address(0), "PriceStabilityPool: WIDO_ADDRESS_INVALID");
    require(_entranceFee != 0, "PriceStabilityPool: ENTRNACE_FEE_INVALID");
    wido = _wido;
    entranceFee = _entranceFee;
  }

  /**
    * @dev Override supportInterface.
    */
  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, AccessControl) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /**
   * @dev Apply for whitelist, need to pay entrance fee
   */
  function applyForWhitelist() external {
    require(!whitelist[msg.sender], "PriceStabilityPool: CALLER_ALREADY_WHITELISTED");
    wido.safeTransferFrom(msg.sender, address(this), entranceFee);
  }

  /**
   * @dev Purchase proper coupon(0, 1, 2)
   * Need to pay coupon fee
   */
  function purchaseCoupon(uint8 _type) external {
    if (_type == 0) {
      wido.safeTransferFrom(msg.sender, address(this), fee0);
    } else  if (_type == 1) {
      wido.safeTransferFrom(msg.sender, address(this), fee1);
    } else if (_type == 2) {
      wido.safeTransferFrom(msg.sender, address(this), fee2);
    } else {
      revert("PriceStabilityPool: COUPON_TYPE_INVALID");
    }

    _mint(msg.sender, ++tokenIds);
    CouponInfo storage newCoupon = coupons[tokenIds];

    if (_type == 0) {
      // one time available
      newCoupon.duration = 1;
    } else  if (_type == 1) {
      newCoupon.duration = 31 days;
    } else {
      newCoupon.duration = 93 days;
    }
  }

  /**
   * @dev Burn `_couponId`
   */
  function burnCoupon(uint256 _couponId) external onlyOperator {
    _burn(_couponId);
  }
}
