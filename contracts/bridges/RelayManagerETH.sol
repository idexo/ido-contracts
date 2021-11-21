// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract RelayManagerETH is AccessControl, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using ECDSA for bytes32;
  
  // The contract owner address
  address public owner;
  // Proposed contract new owner address
  address public newOwner;

  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  // IDO token address
  IERC20 public ido;

  // Bridge wallet for collecting fees
  address public bridgeWallet;
  // Signer check length threshold
  uint8 public threshold = 1;
  // Signer count
  uint8 public signerLength;

  // Fixed Admin Fee in IDO
  uint256 public adminFee; // bps
  uint256 public adminFeeAccumulated;
  uint256 public minTransferAmount;

    // address => signer status
  mapping(address => bool) private _signers;

  // Transfer nonce
  mapping(address => uint256) public nonces;

  // transfer from address => nonce => processed status
  mapping(address => mapping(uint256 => bool)) public processedNonces;
 
  
  // Events
  event Deposited(address indexed from, address indexed receiver, uint256 toChainId, uint256 amount, uint256 nonce);
  event Sent(address indexed receiver, uint256 indexed amount, uint256 indexed transferredAmount, uint256 nonce);
  event AdminFeeChanged(uint256 indexed AdminFee);
  event EthReceived(address indexed sender, uint256 amount);
  event BridgeWalletChanged(address indexed bridgeWallet);
  event ThresholdChanged(uint8 threshold);
  event SignerAdded(address indexed signer);
  event SignerRemoved(address indexed signer);

  constructor(
    IERC20 _ido,
    uint256 _adminFee,
    address _bridgeWallet,
    uint8 _threshold,
    address[] memory signers_
  ) {
    require(_adminFee != 0, "RelayManagerETH: ADMIN_FEE_INVALID");
    require(_threshold >= 1, "RelayManager2Secure: THRESHOLD_INVALID");
    require(_bridgeWallet != address(0), "RelayManager2Secure: BRIDGE_WALLET_ADDRESS_INVALID");
    address sender = _msgSender();

    for (uint8 i = 0; i < signers_.length; i++) {
      if (signers_[i] != address(0) && !_signers[signers_[i]]) {
        _signers[signers_[i]] = true;
        signerLength++;
      }
    }

    // signer length must not be less than threshold
    require(signerLength >= _threshold, "RelayManager2Secure: SIGNERS_NOT_ENOUGH");
    ido = _ido;
    owner = sender;
    adminFee = _adminFee;
    bridgeWallet = _bridgeWallet;
    threshold = _threshold;

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
    * @dev Send (unlock) funds to the receiver to process cross-chain transfer
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

  

  function _send(
    address from,
    address receiver,
    uint256 amount,
    uint256 nonce,
    bytes[] calldata _signatures
  ) internal {
    require(receiver != address(0), "RelayManagerETH: RECEIVER_ZERO_ADDRESS");
    require(amount > adminFee, "RelayManagerETH: SEND_AMOUNT_INVALID");
    require(
      _verify(keccak256(abi.encodePacked(from, receiver, amount, nonce)), _signatures),
      "RelayManager2Secure: INVALID_SIGNATURE"
    );
    require(!processedNonces[from][nonce], 'RelayManager2Secure: TRANSFER_NONCE_ALREADY_PROCESSED');
    // Mark the nonce processed state true to avoid double sending
    processedNonces[from][nonce] = true;
    
    
    // Calculate real amount to transfer considering adminFee and gasFee
    adminFeeAccumulated += adminFee;
    uint256 amountToTransfer = amount - adminFee;
    // Unlock tokens
    ido.safeTransfer(receiver, amountToTransfer);
    ido.safeTransfer(bridgeWallet, adminFee);

    emit Sent(receiver, amount, amountToTransfer, nonce);
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

