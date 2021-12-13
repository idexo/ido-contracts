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

  bytes32 public immutable ONE_TIME_TICKET_HASH = keccak256("One time access");
  bytes32 public immutable ONE_MONTH_TICKET_HASH = keccak256("One month access");
  bytes32 public immutable THREE_MONTH_TICKET_HASH = keccak256("Three month access");
  bytes32 public immutable SIX_MONTH_TICKET_HASH = keccak256("Six month access");
  bytes32 public immutable TWELEVE_MONTH_TICKET_HASH = keccak256("Tweleve month access");
  bytes32 public immutable UNLIMITED_TICKET_HASH = keccak256("Unlimited access");

  // WIDO token address
  IERC20 wido;
  // Access ticket NFT structure
  struct TicketInfo {
    uint256 startTime;
    uint256 duration;
  }
  // Last ticket NFT id, start from 1
  uint256 public ticketIds;
  // Coupon NFT price in WIDO
  uint256 public couponPrice;

  // Ticket id => info
  mapping(uint256 => TicketInfo) public tickets;
  // Ticket type hash => price in WIDO
  mapping(bytes32 => uint256) public ticketPrices;
  // Wallet address => purchased coupon number
  mapping(address => uint256) public coupons;

  constructor(
    string memory _name,
    string memory _symbol,
    IERC20 _wido,
    uint256 _couponPrice
  ) ERC721(_name, _symbol) {
    require(address(_wido) != address(0), "PriceStabilityPool: WIDO_ADDRESS_INVALID");
    require(_couponPrice != 0, "PriceStabilityPool: COUPON_PRICE_INVALID");
    wido = _wido;
    couponPrice = _couponPrice;
  }

  /**
    * @dev Override supportInterface.
    */
  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, AccessControl) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /**
   * @dev Set all access ticket prices in WIDO
   */
  function setAllTicketPrices(
    uint256 _oneTime,
    uint256 _oneMonth,
    uint256 _threeMonth,
    uint256 _sixMonth,
    uint256 _tweleveMonth,
    uint256 _unlimited
  ) external onlyOwner {
    ticketPrices[ONE_TIME_TICKET_HASH] = _oneTime;
    ticketPrices[ONE_MONTH_TICKET_HASH] = _oneMonth;
    ticketPrices[THREE_MONTH_TICKET_HASH] = _threeMonth;
    ticketPrices[SIX_MONTH_TICKET_HASH] = _sixMonth;
    ticketPrices[TWELEVE_MONTH_TICKET_HASH] = _tweleveMonth;
    ticketPrices[UNLIMITED_TICKET_HASH] = _unlimited;
  }

  /**
   * @dev Set `_ticketHash` price
   * `_ticketHash` must be valid
   */
  function setTicketPrice(
    bytes32 _ticketHash,
    uint256 _price
  ) external onlyOwner {
    require(ticketPrices[_ticketHash] != 0, "PriceStabilityPool: TICKET_HASH_INVALID");
    ticketPrices[_ticketHash] = _price;
  }

  /**
   * @dev Purchase access tickets
   * `_ticketHash` must be valid
   */
  function purchaseTicket(bytes32 _ticketHash) external {
    require(whitelist[msg.sender], "PriceStabilityPool: CALLER_NO_WHITELIST");
    uint256 ticketPrice = ticketPrices[_ticketHash];
    require(ticketPrice != 0, "PriceStabilityPool: TICKET_HASH_INVALID");
    wido.safeTransferFrom(msg.sender, address(this), ticketPrice);
    // TODO check multiple purchase or ticket update
    require(balanceOf(msg.sender) == 0, "PriceStabilityPool: CALLER_HAS_ALREADY_TICKET");
    uint256 newId = ++ticketIds;
    tickets[newId].startTime = block.timestamp;
    if (_ticketHash == ONE_TIME_TICKET_HASH) {
      // TODO check again
      tickets[newId].duration = 1;
    } else if (_ticketHash == ONE_MONTH_TICKET_HASH) {
      tickets[newId].duration = 31 days;
    } else if (_ticketHash == THREE_MONTH_TICKET_HASH) {
      tickets[newId].duration = 3 * 31 days;
    } else if (_ticketHash == SIX_MONTH_TICKET_HASH) {
      tickets[newId].duration = 6 * 31 days;
    } else if (_ticketHash == TWELEVE_MONTH_TICKET_HASH) {
      tickets[newId].duration = 12 * 31 days;
    } else {
      // TODO check again
      tickets[newId].duration = 0;
    }
    super._mint(msg.sender, newId);
  }

  /**
   * @dev Purchase coupons
   * TODO check burning expired tickets
   */
  function purchaseCoupon(uint256 _amount) external {
    require(_amount != 0, "PriceStabilityPool: AMOUNT_INVALID");
    uint256 ticketId = tokenOfOwnerByIndex(msg.sender, 0);
    require(ticketId != 0, "PriceStabilityPool: CALLER_NO_ACCESS_TICKET");
    TicketInfo memory ticket = tickets[ticketId];
    require(ticket.startTime != 0, "PriceStabilityPool: ACCESS_TICKET_INVALID");
    require(ticket.duration <= 1 || (ticket.duration > 1 && ticket.startTime + ticket.duration >= block.timestamp), "PriceStabilityPool: ACCESS_TICKET_INVALID");
    wido.safeTransferFrom(msg.sender, address(this), _amount * couponPrice);
    // delete one-time access ticket
    if (ticket.duration == 1) {
      _burn(ticketId);
      delete tickets[ticketId];
    }
  }
}
