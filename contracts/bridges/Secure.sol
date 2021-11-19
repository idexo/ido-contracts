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

  // Wrapped IDO token address
  IWIDO public wIDO;
  // Bridge wallet for collecting fees
  address public bridgeWallet;

  uint8 public threshold = 1;
  uint8 public signerLength;
  uint256 public baseGas;
  uint256 public adminFee; // fixd amount in WIDO
  uint256 public adminFeeAccumulated;

  // address => signer status
  mapping(address => bool) private _signers;
  // Transfer nonce
  mapping(address => uint256) public nonces;
  // transfer from address => nonce => processed status
  mapping(address => mapping(uint256 => bool)) public processedNonces;

  // Events
  event Deposited(address indexed from, address indexed receiver, uint256 toChainId, uint256 amount, uint256 nonce);
  event Sent(address indexed receiver, uint256 indexed amount, uint256 indexed transferredAmount);
  event AdminFeeChanged(uint256 indexed adminFeeBps);
  event EthReceived(address indexed sender, uint256 amount);
  event AdminFeeWithdraw(address indexed receiver, uint256 amount);
  event BridgeWalletChanged(address indexed bridgeWallet);

  constructor(
    IWIDO _wIDO,
    uint256 _adminFee,
    uint8 _threshold,
    address[] memory signers_
  ) {
    require(_adminFee != 0, "RelayManager2Secure: ADMIN_FEE_INVALID");
    require(_threshold >= 1, "RelayManager2Secure: THRESHOLD_INVALID");
    threshold = _threshold;

    for (uint8 i = 0; i < signers_.length; i++) {
      if (signers_[i] != address(0) && !_signers[signers_[i]]) {
        _signers[signers_[i]] = true;
        signerLength++;
      }
    }

    // signer length must not be less than threshold
    require(signerLength >= _threshold, "RelayManager2Secure: SIGNERS_NOT_ENOUGH");

    wIDO = _wIDO;
    adminFee = _adminFee;
    baseGas = 21000; // default block gas limit
  }

  receive() external payable {
    emit EthReceived(msg.sender, msg.value);
  }

  /**************************|
  |          Setters         |
  |_________________________*/

  /**
    * @dev Set admin fee
    * Only `owner` can call
    */
  function setAdminFee(uint256 newAdminFee) external onlyOwner {
    require(newAdminFee != 0, "RelayManager2Secure: ADMIN_FEE_INVALID");
    adminFee = newAdminFee;

    emit AdminFeeChanged(newAdminFee);
  }

  function changeThreshold(
    uint8 newThreshold,
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

    if (signer != address(0) && !_signers[signer]) {
      _signers[signer] = true;
      signerLength++;
    }
  }

  function removeSigner(
    address signer,
    bytes[] calldata signatures
  ) external onlyOwner {
    require(
      verify(keccak256(abi.encodePacked(signer)), signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );

    if (_signers[signer] && --signerLength >= threshold) {
      _signers[signer] = false;
    }
  }

  /**
    * @dev Set base gas
    * Only `owner` can call
    */
  function setBaseGas(uint256 newBaseGas) external onlyOwner {
    baseGas = newBaseGas;
  }

  /**
    * @dev Set bridge wallet address for collecting admin fees
   */
  function setBridgeWallet(address newBridgeWallet) external onlyOwner {
      require(newBridgeWallet != address(0), "RelayManager2Secure: NEW_BRIDGE_WALLET_ADDRESS_INVALID");
      bridgeWallet = newBridgeWallet;

      emit BridgeWalletChanged(newBridgeWallet);
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
    require(amount >= adminFee, "RelayManager2Secure: DEPOSIT_AMOUNT_INVALID");
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

  // /**
  //   * @dev Withdraw admin fee accumulated
  //   * Only `owner` can call
  //   */
  // function withdrawAdminFee(
  //   uint256 amount
  // ) external onlyOwner {
  //   require(bridgeWallet != address(0), "RelayManager2Secure: BRIDGE_WALLET_ADDRESS_INVALID");
  //   require(amount > 0, "RelayManager2Secure: AMOUNT_INVALID");
  //   require(adminFeeAccumulated >= amount, "RelayManager2Secure: INSUFFICIENT_ADMIN_FEE");
  //   adminFeeAccumulated -= amount;
  //   wIDO.safeTransfer(bridgeWallet, amount);

  //   emit AdminFeeWithdraw(bridgeWallet, amount);
  // }

  function _send(
    address from,
    address receiver,
    uint256 amount,
    uint256 nonce,
    bytes[] calldata _signatures
  ) internal {
    require(receiver != address(0), "RelayManager2Secure: RECEIVER_ZERO_ADDRESS");
    require(amount > adminFee, "RelayManager2Secure: SEND_AMOUNT_INVALID");
    require(
      verify(keccak256(abi.encodePacked(from, receiver, amount, nonce)), _signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );
    require(!processedNonces[from][nonce], 'RelayManager2Secure: TRANSFER_NONCE_ALREADY_PROCESSED');

    // Mark the nonce processed state true to avoid double sending
    processedNonces[from][nonce] = true;
    adminFeeAccumulated += adminFee;
    uint256 amountToTransfer = amount - adminFee;
    // Mint tokens
    wIDO.mint(receiver, amountToTransfer);
    // Mint tokens to bridge wallet
    wIDO.mint(bridgeWallet, adminFee);

    emit Sent(receiver, amount, amountToTransfer);
  }

  function isSigner(address _candidate) public view returns (bool) {
    return _signers[_candidate];
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
      if (!_signers[currentSigner]) {
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
