// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IWIDO.sol";

contract RelayManager2Secure is AccessControl, ReentrancyGuard {
  using SafeERC20 for IWIDO;

  mapping(address => bool) private signers;

  // The contract owner address
  address public owner;
  // Proposed contract new owner address
  address public newOwner;

  uint256 public threshold = 1;

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
  mapping(address => mapping(uint => bool)) public processedNonces;
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
    uint256 _adminFee,
    uint256 _threshold,
    address[] memory _signers

  ) {
    require(_adminFee != 0, "RelayManager2: ADMIN_FEE_INVALID");
    threshold = _threshold;
    for (uint256 i = 0; i < _signers.length; i++) {
            signers[_signers[i]] = true;
        }
    address sender = _msgSender();
    wIDO = _wIDO;
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
    require(newAdminFee != 0, "RelayManager2: ADMIN_FEE_INVALID");
    adminFee = newAdminFee;

    emit AdminFeeChanged(newAdminFee);
  }

  // gov
  function changeThreshold(uint256 _newThreshold, bytes[] calldata _signatures)
      external
      onlyOwner
  {
      require(
          verify(
              keccak256(abi.encodePacked(_newThreshold)),
              _signatures
          ),
          "Minter: invalid signature"
      );
      threshold = _newThreshold;
  }

  function addSigner(address _signer, bytes[] calldata _signatures)
        external
        onlyOwner
  {
      require(
          verify(keccak256(abi.encodePacked(_signer)), _signatures),
          "Minter: invalid signature"
      );

      signers[_signer] = true;
  }

  function removeSigner(address _signer, bytes[] calldata _signatures)
      external
      onlyOwner
  {
      require(
          verify(keccak256(abi.encodePacked(_signer)), _signatures),
          "Minter: invalid signature"
      );
      
      signers[_signer] = false;
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
    require(owner == _msgSender(), "RelayManager2: CALLER_NO_OWNER");
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
    require(_newOwner != address(0), "RelayManager2: INVALID_ADDRESS");
    require(_newOwner != owner, "RelayManager2: OWNERSHIP_SELF_TRANSFER");
    newOwner = _newOwner;
  }

  /**
    * @dev The new owner accept an ownership transfer.
    */
  function acceptOwnership() external {
    require(_msgSender() == newOwner, "RelayManager2: CALLER_NO_NEW_OWNER");
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
    address from,
    address receiver,
    uint256 amount,
    bytes32 depositHash,
    uint256 nonce,
    bytes[] calldata signatures
  ) external nonReentrant onlyOperator {
    _send(from, receiver, amount, depositHash, nonce, signatures);
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
    address from,
    address receiver,
    uint256 amount,
    bytes32 depositHash,
    uint256 nonce,
    bytes[] calldata _signatures
  ) internal {
    
    require(receiver != address(0), "RelayManager2: RECEIVER_ZERO_ADDRESS");
    require(amount > minTransferAmount, "RelayManager2: SEND_AMOUNT_INVALID");
    require(amount > adminFee, "RelayManager2: AMOUNT LESS THAN ADMIN FEE");
    require(
      verify(
        keccak256(
            abi.encodePacked(from, receiver, amount, depositHash, nonce)
          ),
        _signatures
        ),
      "RelayerManager2: INVALID_SIGNATURE"
      );
    bytes32 hash = keccak256(abi.encodePacked(from, receiver, amount, depositHash, nonce));
    require(!processedHashes[hash], "RelayManager2: ALREADY_PROCESSED");
    require(processedNonces[from][nonce] == false, 'transfer already processed');
   
    // Mark the nonce processed state true to avoid double sending
    processedNonces[from][nonce] = true;

    // Mark the depositHash state true to avoid double sending
    processedHashes[depositHash] = true;
   
    uint256 amountToTransfer = amount - adminFee;
    // Mint tokens
    wIDO.mint(receiver, amountToTransfer);

    emit Sent(receiver, amount, amountToTransfer, depositHash);
  }

  function recoverSigner(bytes32 message, bytes memory sig)
    internal
    pure
    returns (address)
  {
    bytes32 r;
    bytes32 s;
    uint8 v;
  
    // Check the signature length
    if (sig.length != 65) {
      return (address(0));
    }

    assembly {
        // first 32 bytes, after the length prefix
        r := mload(add(sig, 0x20))
        // second 32 bytes
        s := mload(add(sig, 0x40))
        // final byte (first byte of the next 32 bytes)
        v := byte(0, mload(add(sig, 0x60)))
    }
    // Version of signature should be 27 or 28, but 0 and 1 are also possible versions
    if (v < 27) {
      v += 27;
    }  

        // If the version is correct return the signer address
    if (v != 27 && v != 28) {
      return (address(0));
    } else {
      // solium-disable-next-line arg-overflow
      return ecrecover(message, v, r, s);
    }
  }

 
  function isSigner(address _candidate) public view returns (bool) {
      return signers[_candidate];
  }

  function verify(bytes32 _hash, bytes[] memory _signatures)
        public
        view
        returns (bool)
    {
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
