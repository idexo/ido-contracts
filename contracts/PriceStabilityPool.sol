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
  bytes32 public immutable TWELVE_MONTH_TICKET_HASH = keccak256("Twelve month access");
  bytes32 public immutable UNLIMITED_TICKET_HASH = keccak256("Unlimited access");

  // WIDO token address
  IERC20 public wido;
  // Stable coin address
  IERC20 public usdt;
  // Length of time that price is stable until
  uint256 public stabilityPeriod;
  // Stability starting timestamp
  uint256 public stabilityStartTime;
  // Gas utilization in native token
  uint256 public couponGasPrice;
  // Gas price in stable coin
  uint256 public couponStablePrice;
  // Last stake NFT id, start from 1
  uint256 public lastStakeId;
  // First stake NFT id, start from 1
  uint256 public firstStakeId = 1;
  // Total staked coupon amount
  uint256 public totalCoupon;
  // Entrance fee in basis point, max 1000
  uint256 public entranceFeeBP;
  // Staker wallet array
  address[] public stakers;

  // Access ticket NFT structure
  struct TicketInfo {
    uint256 startTime;
    uint256 duration;
  }

  // Stake NFT id => created coupon amount
  mapping(uint256 => uint256) public stakedCoupons;
  // Staker address => total created coupon amount
  mapping(address => uint256) public couponBalances;
  // Wallet address => ticket info
  mapping(address => TicketInfo) public tickets;
  // Ticket type hash => price in WIDO
  mapping(bytes32 => uint256) public ticketPrices;
  // Wallet address => purchased coupon amount
  mapping(address => uint256) public purchasedCoupons;
  // Staker address => premium (entrance fee)
  mapping(address => uint256) public premiums;

  constructor(
    string memory _name,
    string memory _symbol,
    IERC20 _wido,
    IERC20 _usdt,
    uint256 _stabilityPeriod,
    uint256 _stabilityStartTime,
    uint256 _couponGasPrice,
    uint256 _couponStablePrice,
    uint256 _entranceFeeBP
  ) ERC721(_name, _symbol) {
    require(address(_wido) != address(0), "PriceStabilityPool: WIDO_ADDRESS_INVALID");
    require(address(_usdt) != address(0), "PriceStabilityPool: USDT_ADDRESS_INVALID");
    require(_stabilityPeriod != 0, "PriceStabilityPool: STABILITY_PERIOD_INVALID");
    require(_stabilityStartTime >= block.timestamp, "PriceStabilityPool: STABILITY_START_TIME_INVALID");
    require(_entranceFeeBP <= 1000, "PriceStabilityPool: ENTRANCE_FEE_INVALID");
    wido = _wido;
    usdt = _usdt;
    stabilityPeriod = _stabilityPeriod;
    couponGasPrice = _couponGasPrice;
    couponStablePrice = _couponStablePrice;
    stabilityStartTime = _stabilityStartTime;
    entranceFeeBP = _entranceFeeBP;
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
    uint256 _twelveMonth,
    uint256 _unlimited
  ) external onlyOwner {
    ticketPrices[ONE_TIME_TICKET_HASH] = _oneTime;
    ticketPrices[ONE_MONTH_TICKET_HASH] = _oneMonth;
    ticketPrices[THREE_MONTH_TICKET_HASH] = _threeMonth;
    ticketPrices[SIX_MONTH_TICKET_HASH] = _sixMonth;
    ticketPrices[TWELVE_MONTH_TICKET_HASH] = _twelveMonth;
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
   * @dev Create coupon
   * `msg.sender` must be whitelisted
   * `msg.value` must be sufficient
   * pool stability period must not be ended
   */
  function createCoupon(uint256 _amount) external payable {
    require(whitelist[msg.sender], "PriceStabilityPool: CALLER_NO_WHITELIST");
    require(_amount != 0, "PriceStabilityPool: COUPON_AMOUNT_INVALID");
    require(msg.value >= _amount * couponGasPrice, "PriceStabilityPool: INSUFFICIENT_FUNDS");
    require(block.timestamp <= stabilityStartTime + stabilityPeriod, "PriceStabilityPool: STABILITY_PERIOD_ENDED");
    uint256 newId = ++lastStakeId;
    super._mint(msg.sender, newId);
    stakedCoupons[newId] = _amount;
    if (couponBalances[msg.sender] == 0) {
      stakers.push(msg.sender);
    }
    couponBalances[msg.sender] += _amount;
    totalCoupon += _amount;
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
    require(block.timestamp <= stabilityStartTime + stabilityPeriod, "PriceStabilityPool: STABILITY_PERIOD_ENDED");
    uint256 ticketPrice = ticketPrices[_ticketHash];
    require(ticketPrice != 0, "PriceStabilityPool: TICKET_HASH_INVALID");
    uint256 entranceFee = ticketPrice * entranceFeeBP / 10000;
    wido.safeTransferFrom(msg.sender, address(this), ticketPrice * (10000 + entranceFeeBP) / 10000);
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
    } else if (_ticketHash == TWELVE_MONTH_TICKET_HASH) {
      tickets[msg.sender].duration = 12 * 31 days;
    } else {
      // TODO check again
      tickets[msg.sender].duration = 0;
    }
    _distributeEntranceFee(entranceFee);
  }

  /**
   * @dev Purchase coupons
   * TODO check burning expired tickets
   */
  function purchaseCoupon(uint256 _amount) external {
    require(block.timestamp <= stabilityStartTime + stabilityPeriod, "PriceStabilityPool: STABILITY_PERIOD_ENDED");
    require(_amount != 0 && _amount <= totalCoupon, "PriceStabilityPool: COUPON_AMOUNT_INVALID");
    TicketInfo memory ticket = tickets[msg.sender];
    // TODO check time manage again
    require(ticket.startTime != 0, "PriceStabilityPool: ACCESS_TICKET_INVALID");
    require(ticket.duration <= 1 || (ticket.duration > 1 && ticket.startTime + ticket.duration >= block.timestamp), "PriceStabilityPool: ACCESS_TICKET_INVALID");

    while(_amount > 0) {
      uint256 firstStakeAmount = stakedCoupons[firstStakeId];
      if (firstStakeAmount > _amount) {
        // TODO check fee here
        usdt.safeTransferFrom(msg.sender, ownerOf(firstStakeId), _amount * couponStablePrice);
        stakedCoupons[firstStakeId] -= _amount;
        _amount = 0;
      } else {
        address firstStaker = ownerOf(firstStakeId);
        // TODO check fee here
        usdt.safeTransferFrom(msg.sender, firstStaker, firstStakeAmount * couponStablePrice);
        _burn(firstStakeId);
        totalCoupon -= firstStakeAmount;
        couponBalances[firstStaker] -= firstStakeAmount;
        // remove first staker from `stakers` array
        if (couponBalances[firstStaker] == 0) {
          for (uint256 i = 0; i < stakers.length; i++) {
            if (stakers[i] == firstStaker) {
              stakers[i] = stakers[stakers.length - 1];
              stakers.pop();
              break;
            }
          }
        }
        firstStakeId++;
        _amount -= firstStakeAmount;
      }
    }

    // delete one-time access ticket
    if (ticket.duration == 1) {
      delete tickets[msg.sender];
    }
  }

  /**
   * @dev Claim premium
   * `_amount` must not be zero and less than premium
   */
  function claim(uint256 _amount) external nonReentrant {
    require(_amount != 0 && _amount <= premiums[msg.sender], "PriceStabilityPool: CLAIM_AMOUNT_INVALID");
    wido.safeTransfer(msg.sender, _amount);
    premiums[msg.sender] -= _amount;
  }

  /**
   * @dev Distribute entrance fee from access ticket purchase to stake holders
   */
  function _distributeEntranceFee(uint256 _fee) private {
    require(_fee != 0, "PriceStabilityPool: INVALID_FEE");
    for (uint256 i = 0; i < stakers.length; i++) {
      address staker = stakers[i];
      premiums[staker] += _fee * couponBalances[staker] / totalCoupon;
    }
  }
}
