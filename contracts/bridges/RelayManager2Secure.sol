// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IWIDO.sol";
import "../lib/Operatorable.sol";

contract RelayManager2Secure is Operatorable {
  using SafeERC20 for IWIDO;
  using ECDSA for bytes32;

  // Wrapped IDO token address
  IWIDO public wIDO;
  // Bridge wallet for collecting fees
  address public bridgeWallet;
  // Signer check length threshold
  uint8 public threshold = 1;
  // Signer count
  uint8 public signerLength;
  // Fixed admin fee in WIDO
  uint256 public adminFee;
  uint256 public adminFeeAccumulated;

  // address => signer status
  mapping(address => bool) private _signers;
  // address => transfer nonce
  mapping(address => uint256) public nonces;
  // transfer from address => nonce => processed status
  mapping(address => mapping(uint256 => bool)) public processedNonces;

  // Events
  event Deposited(address indexed from, address indexed receiver, uint256 toChainId, uint256 amount, uint256 nonce);
  event Sent(address indexed receiver, uint256 indexed amount, uint256 indexed transferredAmount);
  event AdminFeeChanged(uint256 indexed adminFeeBps);
  event BridgeWalletChanged(address indexed bridgeWallet);
  event ThresholdChanged(uint8 threshold);
  event SignerAdded(address indexed signer);
  event SignerRemoved(address indexed signer);

  constructor(
    IWIDO _wIDO,
    uint256 _adminFee,
    address _bridgeWallet,
    uint8 _threshold,
    address[] memory signers_
  ) {
    require(_adminFee != 0, "RelayManager2Secure: ADMIN_FEE_INVALID");
    require(_threshold >= 1, "RelayManager2Secure: THRESHOLD_INVALID");
    require(_bridgeWallet != address(0), "RelayManager2Secure: BRIDGE_WALLET_ADDRESS_INVALID");

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
    bridgeWallet = _bridgeWallet;
    threshold = _threshold;
  }

  /**************************|
  |          Setters         |
  |_________________________*/

  /**
    * @dev Set admin fee
    */
  function setAdminFee(
    uint256 newAdminFee,
    bytes[] calldata signatures
  ) external onlyOperator {
    require(newAdminFee != 0, "RelayManager2Secure: ADMIN_FEE_INVALID");
    require(
      _verify(keccak256(abi.encodePacked(newAdminFee)), signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );
    adminFee = newAdminFee;

    emit AdminFeeChanged(newAdminFee);
  }

  /**
    * @dev Set threshold
    */
  function setThreshold(
    uint8 newThreshold,
    bytes[] calldata signatures
  ) external onlyOperator {
    require(newThreshold >= 1, "RelayManager2Secure: THRESHOLD_INVALID");
    require(
      _verify(keccak256(abi.encodePacked(newThreshold)), signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );
    threshold = newThreshold;

    emit ThresholdChanged(newThreshold);
  }

  /**
    * @dev Add new signer
    * `signer` must not be zero address
    */
  function addSigner(
    address signer,
    bytes[] calldata signatures
  ) external onlyOperator {
    require(
      _verify(keccak256(abi.encodePacked(signer)), signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );

    if (signer != address(0) && !_signers[signer]) {
      _signers[signer] = true;
      signerLength++;
    }

    emit SignerAdded(signer);
  }

  /**
    * @dev Remove signer
    */
  function removeSigner(
    address signer,
    bytes[] calldata signatures
  ) external onlyOperator {
    require(
      _verify(keccak256(abi.encodePacked(signer)), signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );

    if (_signers[signer] && --signerLength >= threshold) {
      _signers[signer] = false;
    }

    emit SignerRemoved(signer);
  }

  /**
    * @dev Set bridge wallet address for collecting admin fees
   */
  function setBridgeWallet(
    address newBridgeWallet,
    bytes[] calldata signatures
  ) external onlyOperator {
      require(newBridgeWallet != address(0), "RelayManager2Secure: BRIDGE_WALLET_ADDRESS_INVALID");
      require(
        _verify(keccak256(abi.encodePacked(newBridgeWallet)), signatures),
        "RelayManager2Secure: INVALID_SIGNATURE"
      );
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
    */
  function send(
    address from,
    address receiver,
    uint256 amount,
    uint256 nonce,
    bytes[] calldata signatures
  ) external onlyOperator {
    _send(from, receiver, amount, nonce, signatures);
  }

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
      _verify(keccak256(abi.encodePacked(from, receiver, amount, nonce)), _signatures),
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

  /**
    * @dev Check signer status of `_candidate`
   */
  function isSigner(address _candidate) public view returns (bool) {
    return _signers[_candidate];
  }

  function _verify(
    bytes32 _hash,
    bytes[] memory _signatures
  ) private view returns (bool) {
    bytes32 h = _hash.toEthSignedMessageHash();
    address lastSigner = address(0x0);
    address currentSigner;

    for (uint256 i = 0; i < _signatures.length; i++) {
      currentSigner = h.recover( _signatures[i]);

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
