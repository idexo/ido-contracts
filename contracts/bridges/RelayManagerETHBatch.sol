// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

contract RelayManagerETH is AccessControl, ReentrancyGuard {
  using SafeERC20 for IERC20;
  // The contract owner address
  address public owner;
  // Proposed contract new owner address
  address public newOwner;

  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  // IDO token address
  IERC20 public ido;

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
    IERC20 _ido,
    uint256 _adminFee
  ) {
    require(_adminFee != 0, "RelayManagerETH: ADMIN_FEE_INVALID");
    address sender = _msgSender();
    ido = _ido;
    owner = sender;
    adminFee = _adminFee;
    baseGas = 21000; // default block gas limit

    _setupRole(DEFAULT_ADMIN_ROLE, sender);
    _setupRole(OPERATOR_ROLE, sender);

    emit OwnershipTransferred(address(0), sender);
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
    require(newAdminFee != 0, "RelayManagerETH: ADMIN_FEE_INVALID");
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

  /****************************|
  |          Ownership         |
  |___________________________*/

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /**
    * @dev Throws if called by any account other than the owner.
    */
  modifier onlyOwner() {
    require(owner == _msgSender(), "RelayManagerETH: CALLER_NO_OWNER");
    _;
  }

  /**
    * @dev Leaves the contract without owner. It will not be possible to call
    * `onlyOwner` functions anymore. Can only be called by the current owner.
    *
    * NOTE: Renouncing ownership will leave the contract without an owner,
    * thereby removing any functionality that is only available to the owner.
    */
  function renounceOwnership() external onlyOwner {
    emit OwnershipTransferred(owner, address(0));
    owner = address(0);
  }

  /**
    * @dev Transfer the contract ownership.
    * The new owner still needs to accept the transfer.
    * can only be called by the contract owner.
    */
  function transferOwnership(address _newOwner) external onlyOwner {
    require(_newOwner != address(0), "RelayManagerETH: INVALID_ADDRESS");
    require(_newOwner != owner, "RelayManagerETH: OWNERSHIP_SELF_TRANSFER");
    newOwner = _newOwner;
  }

  /**
    * @dev The new owner accept an ownership transfer.
    */
  function acceptOwnership() external {
    require(_msgSender() == newOwner, "RelayManagerETH: CALLER_NO_NEW_OWNER");
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
    newOwner = address(0);
  }

  /***********************|
  |          Role         |
  |______________________*/

  /**
    * @dev Restricted to members of the operator role.
    */
  modifier onlyOperator() {
    require(hasRole(OPERATOR_ROLE, _msgSender()), "RelayManagerETH: CALLER_NO_OPERATOR_ROLE");
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
    * @dev Deposit (lock) funds to the relay contract for cross-chain transfer
    */
  function deposit(
    address receiver,
    uint256 amount,
    uint256 toChainId
  ) external {
    require(amount >= minTransferAmount, "RelayManagerETH: DEPOSIT_AMOUNT_INVALID");
    require(receiver != address(0), "RelayManagerETH: RECEIVER_ZERO_ADDRESS");
    address sender = _msgSender();
    // Lock tokens
    ido.safeTransferFrom(sender, address(this), amount);

    emit Deposited(sender, receiver, toChainId, amount, nonces[sender]++);
  }

  /**
    * @dev Permit and deposit (lock) funds to the relay contract for cross-chain transfer
    */
  function permitAndDeposit(
    address receiver,
    uint256 amount,
    uint256 toChainId,
    PermitRequest calldata permitOptions
  ) external {
    require(amount > 0, "RelayManagerETH: DEPOSIT_AMOUNT_INVALID");
    require(receiver != address(0), "RelayManagerETH: RECEIVER_ZERO_ADDRESS");
    address sender = _msgSender();
    // Approve the relay manager contract to spend tokens on behalf of `sender`
    IERC20Permit(address(ido)).permit(_msgSender(), address(this), amount, permitOptions.deadline, permitOptions.v, permitOptions.r, permitOptions.s);
    // Lock tokens
    ido.safeTransferFrom(sender, address(this), amount);

    emit Deposited(sender, receiver, toChainId, amount, nonces[sender]++);
  }

  /**
    * @dev Send (unlock) funds to the receiver to process cross-chain transfer
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

  /**
    * @dev Batch version of {send}
    */
  function sendBatch(
    address[] memory receivers,
    uint256[] memory amounts,
    bytes32[] memory depositHashes,
    uint256 gasPrice
  ) external nonReentrant onlyOperator {
    require(receivers.length == amounts.length && amounts.length == depositHashes.length, "RelayManagerETHBatch: PARAMS_LENGTH_MISMATCH");
    for (uint256 i = 0; i < receivers.length; i++) {
      _send(receivers[i], amounts[i], depositHashes[i], gasPrice);
    }
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
    require(amount > 0, "RelayManagerETH: AMOUNT_INVALID");
    require(adminFeeAccumulated >= amount, "RelayManagerETH: INSUFFICIENT_ADMIN_FEE");
    adminFeeAccumulated -= amount;
    ido.safeTransfer(receiver, amount);

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
    require(amount > 0, "RelayManagerETH: AMOUNT_INVALID");
    require(gasFeeAccumulated >= amount, "RelayManagerETH: INSUFFICIENT_GAS_FEE");
    gasFeeAccumulated -= amount;
    ido.safeTransfer(receiver, amount);

    emit GasFeeWithdraw(receiver, amount);
  }

  function _send(
    address receiver,
    uint256 amount,
    bytes32 depositHash,
    uint256 gasPrice
  ) private {
    uint256 initialGas = gasleft();
    require(receiver != address(0), "RelayManagerETH: RECEIVER_ZERO_ADDRESS");
    require(amount > minTransferAmount, "RelayManagerETH: SEND_AMOUNT_INVALID");
    require(ido.balanceOf(address(this)) >= amount, "RelayManagerETH: INSUFFICIENT_LIQUIDITY");
    bytes32 hash = keccak256(abi.encodePacked(depositHash, address(ido), receiver, amount));
    require(!processedHashes[hash], "RelayManagerETH: ALREADY_PROCESSED");
    // Mark the depositHash state true to avoid double sending
    processedHashes[hash] = true;
    // Calculate adminFee
    uint256 calculatedAdminFee = amount * adminFee / 10000;
    adminFeeAccumulated += calculatedAdminFee;
    // Calculate total used gas price for sending
    uint256 totalGasUsed = initialGas - gasleft();
    totalGasUsed += baseGas;
    gasFeeAccumulated += totalGasUsed * gasPrice;
    // Calculate real amount to transfer considering adminFee and gasFee
    uint256 amountToTransfer = amount - calculatedAdminFee - totalGasUsed * gasPrice;
    // Unlock tokens
    ido.safeTransfer(receiver, amountToTransfer);

    emit Sent(receiver, amount, amountToTransfer, depositHash);
  }
}
