// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IWIDO.sol";
import "../lib/Operatorable.sol";

contract RelayManager2Secure is Operatorable, ReentrancyGuard {
  using SafeERC20 for IWIDO;
  
  // ERC20Permit
  struct PermitRequest {
    uint256 nonce;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  mapping(address => bool) private signers;

  uint256 public threshold = 1;

  // Wrapped IDO token address
  IWIDO public wIDO;

  uint256 public baseGas;
  uint256 public adminFeeBps; // bps
  uint256 public adminFeeAccumulated;
  uint256 public gasFeeAccumulated;
  uint256 public minTransferAmount;

  // Transfer nonce
  mapping(address => uint256) public nonces;
  // transfer from address => nonce => processed status
  mapping(address => mapping(uint256 => bool)) public processedNonces;  

  // Events
  event Deposited(address indexed from, address indexed receiver, uint256 toChainId, uint256 amount, uint256 nonce);
  event Sent(address indexed receiver, uint256 indexed amount, uint256 indexed transferredAmount);
  event AdminFeeBpsChanged(uint256 indexed adminFeeBps);
  event EthReceived(address indexed sender, uint256 amount);
  event AdminFeeWithdraw(address indexed receiver, uint256 amount);
  event GasFeeWithdraw(address indexed receiver, uint256 amount);

  constructor(
    IWIDO _wIDO,
    uint256 _adminFeeBps,
    uint256 _threshold,
    address[] memory _signers
  ) {
    require(_adminFeeBps <= 1000, "RelayManager2Secure: ADMIN_FEE_BPS_INVALID");
    require(_threshold >= 1, "RelayManager2Secure: THRESHOLD_INVALID");
    require(_signers.length >= _threshold, "RelayManager2Secure: SIGNERS_INVALID");
    threshold = _threshold;

    for (uint256 i = 0; i < _signers.length; i++) {
      if (_signers[i] != address(0)) {
        signers[_signers[i]] = true;
      }
    }

    wIDO = _wIDO;
    adminFeeBps = _adminFeeBps;
    baseGas = 21000; // default block gas limit
  }

  receive() external payable {
    emit EthReceived(msg.sender, msg.value);
  }

  /**************************|
  |          Setters         |
  |_________________________*/

  /**
    * @dev Set admin fee bps
    * Only `owner` can call
    */
  function setAdminFeeBps(uint256 newAdminFeeBps) external onlyOwner {
    require(newAdminFeeBps <= 1000, "RelayManager2Secure: ADMIN_FEE_BPS_INVALID");
    adminFeeBps = newAdminFeeBps;

    emit AdminFeeBpsChanged(newAdminFeeBps);
  }

  function changeThreshold(
    uint256 newThreshold, 
    bytes[] calldata signatures
  ) external onlyOwner {
    require(newThreshold >= 1, "RelayManager2Secure: THRESHOLD_INVALID");
    require(
      verify(keccak256(abi.encodePacked(newThreshold)), signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );
    threshold = newThreshold;
  }

  function addSigner(
    address signer, 
    bytes[] calldata signatures
  ) external onlyOwner {
    require(
      verify(keccak256(abi.encodePacked(signer)), signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );

    signers[signer] = true;
  }

  function removeSigner(
    address signer, 
    bytes[] calldata signatures
  ) external onlyOwner {
    require(
      verify(keccak256(abi.encodePacked(signer)), signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );
    
    signers[signer] = false;
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
    require(amount >= minTransferAmount, "RelayManager2Secure: DEPOSIT_AMOUNT_INVALID");
    require(receiver != address(0), "RelayManager2Secure: RECEIVER_ZERO_ADDRESS");
    // Burn tokens
    wIDO.burn(msg.sender, amount);

    emit Deposited(msg.sender, receiver, toChainId, amount, nonces[msg.sender]++);
  }

  /**
    * @dev Send (mint) funds to the receiver to process cross-chain transfer
    * `depositHash = keccak256(abi.encodePacked(senderAddress, tokenAddress, nonce))`
    */
  function send(
    address from,
    address receiver,
    uint256 amount,
    uint256 nonce,
    bytes[] calldata signatures
  ) external nonReentrant onlyOperator {
    _send(from, receiver, amount, nonce, signatures);
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
    require(amount > 0, "RelayManager2Secure: AMOUNT_INVALID");
    require(adminFeeAccumulated >= amount, "RelayManager2Secure: INSUFFICIENT_ADMIN_FEE");
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
    require(amount > 0, "RelayManager2Secure: AMOUNT_INVALID");
    require(gasFeeAccumulated >= amount, "RelayManager2Secure: INSUFFICIENT_GAS_FEE");
    gasFeeAccumulated -= amount;
    wIDO.safeTransfer(receiver, amount);

    emit GasFeeWithdraw(receiver, amount);
  }

  function _send(
    address from,
    address receiver,
    uint256 amount,    
    uint256 nonce,
    bytes[] calldata _signatures
  ) internal {    
    require(receiver != address(0), "RelayManager2Secure: RECEIVER_ZERO_ADDRESS");
    require(amount > minTransferAmount, "RelayManager2Secure: SEND_AMOUNT_INVALID");
    require(
      verify(keccak256(abi.encodePacked(from, receiver, amount, nonce)), _signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );    
    require(!processedNonces[from][nonce], 'RelayManager2Secure: TRANSFER_NONCE_ALREADY_PROCESSED');
   
    // Mark the nonce processed state true to avoid double sending
    processedNonces[from][nonce] = true;
    // Calculate adminFee
    uint256 calculatedAdminFee = amount * adminFeeBps / 10000;
    adminFeeAccumulated += calculatedAdminFee;
    require(amount > calculatedAdminFee, "RelayManager2Secure: INSUFFICIENT_TRANSFER_AMOUNT");
    uint256 amountToTransfer = amount - calculatedAdminFee;
    // Mint tokens
    wIDO.mint(receiver, amountToTransfer);

    emit Sent(receiver, amount, amountToTransfer);
  }

  function verify(
    bytes32 _hash, 
    bytes[] memory _signatures
  ) public view returns (bool) {
    bytes32 h = ECDSA.toEthSignedMessageHash(_hash);
    address lastSigner = address(0x0);
    address currentSigner;

    for (uint256 i = 0; i < _signatures.length; i++) {
      currentSigner = ECDSA.recover(h, _signatures[i]);

      if (currentSigner <= lastSigner) {
        return false;
      }
      if (!signers[currentSigner]) {
        return false;
      }
      lastSigner = currentSigner;
    }

    if (_signatures.length < threshold) {
      return false;
    }

    return true;
  }
}
