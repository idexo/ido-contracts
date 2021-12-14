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
  // Stable coin address
  IERC20 usdt;
  // Length of time that price is stable until
  uint256 public stabilityPeriod;
  // Deployed timestamp
  uint256 public deployedTime;
  // Gas utilization in native token
  uint256 public couponGasPrice;
  // Gas price in stable coin
  uint256 public couponStablePrice;
  // Last stake NFT id, start from 1
  uint256 public stakeId;

  // Access ticket NFT structure
  struct TicketInfo {
    uint256 startTime;
    uint256 duration;
  }

  // stake NFT id => created coupon amount
  mapping(uint256 => uint256) public stakedCoupons;
  // Wallet address => ticket info
  mapping(address => TicketInfo) public tickets;
  // Ticket type hash => price in WIDO
  mapping(bytes32 => uint256) public ticketPrices;
  // Wallet address => purchased coupon amount
  mapping(address => uint256) public purchasedCoupons;

  constructor(
    string memory _name,
    string memory _symbol,
    IERC20 _wido,
    IERC20 _usdt,
    uint256 _stabilityPeriod,
    uint256 _couponGasPrice,
    uint256 _couponStablePrice
  ) ERC721(_name, _symbol) {
    require(address(_wido) != address(0), "PriceStabilityPool: WIDO_ADDRESS_INVALID");
    require(address(_usdt) != address(0), "PriceStabilityPool: USDT_ADDRESS_INVALID");
    require(_stabilityPeriod != 0, "PriceStabilityPool: STABILITY_PERIOD_INVALID");
    wido = _wido;
    usdt = _usdt;
    stabilityPeriod = _stabilityPeriod;
    couponGasPrice = _couponGasPrice;
    couponStablePrice = _couponStablePrice;
    deployedTime = block.timestamp;
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

  function createCoupon(uint256 _amount) external payable {
    require(whitelist[msg.sender], "PriceStabilityPool: CALLER_NO_WHITELIST");
    require(_amount != 0, "PriceStabilityPool: COUPON_AMOUNT_INVALID");
    require(msg.value >= _amount * couponGasPrice, "PriceStabilityPool: INSUFFICIENT_FUNDS");
    require(block.timestamp <= deployedTime + stabilityPeriod, "PriceStabilityPool: STABILITY_PERIOD_ENDED");
    uint256 newId = ++stakeId;
    super._mint(msg.sender, newId);
    stakedCoupons[newId] = _amount;
    // return change if any
    uint256 change = msg.value - _amount * couponGasPrice;
    if (change > 0) {
      (bool success, ) = payable(msg.sender).call{value: change}("");
      require(success, "PriceStabilityPool: TRANSFER_FAILED");
    }
  }

  /**
   * @dev Purchase access tickets
   * `_ticketHash` must be valid
   */
  // TODO check multiple ticket purchase or ticket update
  function purchaseTicket(bytes32 _ticketHash) external {
    uint256 ticketPrice = ticketPrices[_ticketHash];
    require(ticketPrice != 0, "PriceStabilityPool: TICKET_HASH_INVALID");
    wido.safeTransferFrom(msg.sender, address(this), ticketPrice);
    require(tickets[msg.sender].startTime == 0, "PriceStabilityPool: CALLER_HAS_ALREADY_TICKET");
    tickets[msg.sender].startTime = block.timestamp;
    if (_ticketHash == ONE_TIME_TICKET_HASH) {
      // TODO check again
      tickets[msg.sender].duration = 1;
    } else if (_ticketHash == ONE_MONTH_TICKET_HASH) {
      tickets[msg.sender].duration = 31 days;
    } else if (_ticketHash == THREE_MONTH_TICKET_HASH) {
      tickets[msg.sender].duration = 3 * 31 days;
    } else if (_ticketHash == SIX_MONTH_TICKET_HASH) {
      tickets[msg.sender].duration = 6 * 31 days;
    } else if (_ticketHash == TWELEVE_MONTH_TICKET_HASH) {
      tickets[msg.sender].duration = 12 * 31 days;
    } else {
      // TODO check again
      tickets[msg.sender].duration = 0;
    }
  }

  /**
   * @dev Purchase coupons
   * TODO check burning expired tickets
   */
  function purchaseCoupon(uint256 _amount) external {
    require(_amount != 0, "PriceStabilityPool: COUPON_AMOUNT_INVALID");
    // uint256 ticketId = tokenOfOwnerByIndex(msg.sender, 0);
    // require(ticketId != 0, "PriceStabilityPool: CALLER_NO_ACCESS_TICKET");
    TicketInfo memory ticket = tickets[msg.sender];
    require(ticket.startTime != 0, "PriceStabilityPool: ACCESS_TICKET_INVALID");
    require(ticket.duration <= 1 || (ticket.duration > 1 && ticket.startTime + ticket.duration >= block.timestamp), "PriceStabilityPool: ACCESS_TICKET_INVALID");
    usdt.safeTransferFrom(msg.sender, address(this), _amount * couponStablePrice);
    // delete one-time access ticket
    if (ticket.duration == 1) {
      delete tickets[msg.sender];
    }
  }
}
