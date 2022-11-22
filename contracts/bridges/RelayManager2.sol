// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "../interfaces/IWIDO.sol";

contract RelayManager2 is AccessControl, ReentrancyGuard, Ownable2Step {
  using SafeERC20 for IWIDO;

  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  // Wrapped IDO token address
  IWIDO public wIDO;

  uint256 public baseGas;
  uint256 public adminFee; // bps
  uint256 public adminFeeAccumulated;
  uint256 public gasFeeAccumulated;
  uint256 public minTransferAmount;

  // Transfer nonce
  mapping(address => uint256) public nonces;
  // Transfer hash processed status
  mapping(bytes32 => bool) public processedHashes;
  // ERC20Permit
  struct PermitRequest {
    uint256 nonce;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }
  // Events
  event Deposited(address indexed from, address indexed receiver, uint256 toChainId, uint256 amount, uint256 nonce);
  event Sent(address indexed receiver, uint256 indexed amount, uint256 indexed transferredAmount, bytes32 depositHash);
  event AdminFeeChanged(uint256 indexed AdminFee);
  event EthReceived(address indexed sender, uint256 amount);
  event AdminFeeWithdraw(address indexed receiver, uint256 amount);
  event GasFeeWithdraw(address indexed receiver, uint256 amount);

  constructor(
    IWIDO _wIDO,
    uint256 _adminFee
  ) {
    require(_adminFee != 0, "RelayManager2: ADMIN_FEE_INVALID");
    address sender = _msgSender();
    wIDO = _wIDO;
    adminFee = _adminFee;
    baseGas = 21000; // default block gas limit

    _setupRole(DEFAULT_ADMIN_ROLE, sender);
    _setupRole(OPERATOR_ROLE, sender);
  }

  receive() external payable {
    emit EthReceived(_msgSender(), msg.value);
  }

  /**************************|
  |          Setters         |
  |_________________________*/

  /**
    * @dev Set admin fee bps
    * Only `owner` can call
    */
  function setAdminFee(uint256 newAdminFee) external onlyOwner {
    require(newAdminFee != 0, "RelayManager2: ADMIN_FEE_INVALID");
    adminFee = newAdminFee;

    emit AdminFeeChanged(newAdminFee);
  }

  /**
    * @dev Set base gas
    * Only `owner` can call
    */
  function setBaseGas(uint256 newBaseGas) external onlyOwner {
    baseGas = newBaseGas;
  }

  /**
    * @dev Set minimum transfer amount
    * Only `owner` can call
    */
  function setMinTransferAmount(uint256 newMinTransferAmount) external onlyOwner {
    minTransferAmount = newMinTransferAmount;
  }

  /***********************|
  |          Role         |
  |______________________*/

  /**
    * @dev Restricted to members of the operator role.
    */
  modifier onlyOperator() {
    require(hasRole(OPERATOR_ROLE, _msgSender()), "RelayManager2: CALLER_NO_OPERATOR_ROLE");
    _;
  }

  /**
    * @dev Add an account to the operator role.
    */
  function addOperator(address account) public onlyOwner {
    grantRole(OPERATOR_ROLE, account);
  }

  /**
    * @dev Remove an account from the operator role.
    */
  function removeOperator(address account) public onlyOwner {
    revokeRole(OPERATOR_ROLE, account);
  }

  /**
    * @dev Check if an account is operator.
    */
  function checkOperator(address account) public view returns (bool) {
    return hasRole(OPERATOR_ROLE, account);
  }

  /***************************|
  |          Transfer         |
  |__________________________*/

  /**
    * @dev Deposit (burn) funds to the relay contract for cross-chain transfer
    */
  function deposit(
    address receiver,
    uint256 amount,
    uint256 toChainId
  ) external {
    require(amount >= minTransferAmount, "RelayManager2: DEPOSIT_AMOUNT_INVALID");
    require(receiver != address(0), "RelayManager2: RECEIVER_ZERO_ADDRESS");
    address sender = _msgSender();
    // Burn tokens
    wIDO.burn(_msgSender(), amount);

    emit Deposited(sender, receiver, toChainId, amount, nonces[sender]++);
  }

  /**
    * @dev Send (mint) funds to the receiver to process cross-chain transfer
    * `depositHash = keccak256(abi.encodePacked(senderAddress, tokenAddress, nonce))`
    */
  function send(
    address receiver,
    uint256 amount,
    bytes32 depositHash,
    uint256 gasPrice
  ) external nonReentrant onlyOperator {
    _send(receiver, amount, depositHash, gasPrice);
  }

  /**********************|
  |          Fee         |
  |_____________________*/

  /**
    * @dev Withdraw admin fee accumulated
    * Only `owner` can call
    */
  function withdrawAdminFee(
    address receiver,
    uint256 amount
  ) external onlyOwner {
    require(amount > 0, "RelayManager2: AMOUNT_INVALID");
    require(adminFeeAccumulated >= amount, "RelayManager2: INSUFFICIENT_ADMIN_FEE");
    adminFeeAccumulated -= amount;
    wIDO.safeTransfer(receiver, amount);

    emit AdminFeeWithdraw(receiver, amount);
  }

  /**
    * @dev Withdraw gas fee accumulated
    * Only `owner` can call
    */
  function withdrawGasFee(
    address receiver,
    uint256 amount
  ) external onlyOwner {
    require(amount > 0, "RelayManager2: AMOUNT_INVALID");
    require(gasFeeAccumulated >= amount, "RelayManager2: INSUFFICIENT_GAS_FEE");
    gasFeeAccumulated -= amount;
    wIDO.safeTransfer(receiver, amount);

    emit GasFeeWithdraw(receiver, amount);
  }

  function _send(
    address receiver,
    uint256 amount,
    bytes32 depositHash,
    uint256 gasPrice
  ) internal {
    uint256 initialGas = gasleft();
    require(receiver != address(0), "RelayManager2: RECEIVER_ZERO_ADDRESS");
    require(amount > minTransferAmount, "RelayManager2: SEND_AMOUNT_INVALID");
    bytes32 hash = keccak256(abi.encodePacked(depositHash, address(wIDO), receiver, amount));
    require(!processedHashes[hash], "RelayManager2: ALREADY_PROCESSED");

    // Mark the depositHash state true to avoid double sending
    processedHashes[depositHash] = true;
    // Calculate adminFee
    uint256 calculatedAdminFee = amount * adminFee / 10000;
    adminFeeAccumulated += calculatedAdminFee;
    // Calculate total used gas price for sending
    uint256 totalGasUsed = initialGas - gasleft();
    totalGasUsed += baseGas;
    gasFeeAccumulated += totalGasUsed * gasPrice;
    // Calculate real amount to transfer considering adminFee and gasFee
    require(amount > calculatedAdminFee + totalGasUsed * gasPrice, "RelayManager2: INSUFFICIENT_TRANSFER_AMOUNT");
    uint256 amountToTransfer = amount - calculatedAdminFee - totalGasUsed * gasPrice;
    // Mint tokens
    wIDO.mint(receiver, amountToTransfer);

    emit Sent(receiver, amount, amountToTransfer, depositHash);
  }
}
