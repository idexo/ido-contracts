// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "../interfaces/IWIDO.sol";

contract RelayManager2 is Pausable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IWIDO;
    // The contract owner address
    address public owner;
    // Proposed contract new owner address
    address public newOwner;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    // Wrapped IDO token address
    IWIDO public wIDO;

    uint256 public baseGas;

    uint256 public adminFee; // bps
    uint256 public adminFeeAccumulated;
    uint256 public gasFeeAccumulated;

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
    event TrustedForwarderChanged(address indexed TrustedForwarder);
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

    /**
     * @dev Set base gas
     * Only `owner` can call
     */
    function setBaseGas(uint256 newBaseGas) external onlyOwner {
        baseGas = newBaseGas;
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
        require(!hasRole(OPERATOR_ROLE, account), "RelayManager2: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     */
    function removeOperator(address account) public onlyOwner {
        require(hasRole(OPERATOR_ROLE, account), "RelayManager2: NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     */
    function checkOperator(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /********************************|
    |          Pause/Unpause         |
    |_______________________________*/

    /**
     * @dev Pause the liquidity pool contract
     * Only `operator` can call
     */
    function pause() external onlyOperator {
        super._pause();
    }

    /**
     * @dev Unause the liquidity pool contract
     * Only `operator` can call
     */
    function unpause() external onlyOperator {
        super._unpause();
    }

    /***************************|
    |          Transfer         |
    |__________________________*/

    /**
     * @dev Deposit funds to the relay contract for cross-chain transfer
     */
    function deposit(
        address receiver,
        uint256 amount,
        uint256 toChainId
    ) external whenNotPaused {
        require(amount > 0, "RelayManager2: DEPOSIT_AMOUNT_INVALID");
        require(receiver != address(0), "RelayManager2: RECEIVER_ZERO_ADDRESS");
        address sender = _msgSender();
        // Burn tokens
        wIDO.burn(_msgSender(), amount);

        emit Deposited(sender, receiver, toChainId, amount, nonces[sender]++);
    }

    /**
     * @dev Deposit funds to the relay contract for cross-chain transfer
     */
    function permitAndDeposit(
        address receiver,
        uint256 amount,
        uint256 toChainId,
        PermitRequest calldata permitOptions
    ) external whenNotPaused {
        require(amount > 0, "RelayManager2: DEPOSIT_AMOUNT_INVALID");
        require(receiver != address(0), "RelayManager2: RECEIVER_ZERO_ADDRESS");
        address sender = _msgSender();
        // Approve the relay manager contract to spend tokens on behalf of `sender`
        IERC20Permit(address(wIDO)).permit(_msgSender(), address(this), amount, permitOptions.deadline, permitOptions.v, permitOptions.r, permitOptions.s);
        // Burn tokens
        wIDO.burn(_msgSender(), amount);

        emit Deposited(sender, receiver, toChainId, amount, nonces[sender]++);
    }

    /**
     * @dev Send funds to the receiver to process cross-chain transfer
     */
    function send(
        address receiver,
        uint256 amount,
        bytes32 depositHash,
        uint256 gasPrice
    ) external nonReentrant whenNotPaused onlyOperator {
        uint256 initialGas = gasleft();
        require(receiver != address(0), "RelayManager2: RECEIVER_ZERO_ADDRESS");
        require(amount > 0, "RelayManager2: SEND_AMOUNT_INVALID");
        require(!processedHashes[depositHash], "RelayManager2: ALREADY_PROCESSED");
        require(wIDO.balanceOf(address(this)) >= amount, "RelayManager2: INSUFFICIENT_LIQUIDITY");

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
        uint256 amountToTransfer = amount - calculatedAdminFee - totalGasUsed * gasPrice;
        // Mint tokens
        wIDO.mint(receiver, amountToTransfer);

        emit Sent(receiver, amount, amountToTransfer, depositHash);
    }

    /**********************|
    |          Fee         |
    |_____________________*/

    /**
     * @dev Withdraw admin fee accumulated
     * Only operators can call
     */
    function withdrawAdminFee(
        address receiver,
        uint256 amount
    ) external onlyOperator whenNotPaused {
        require(amount > 0, "RelayManager2: RECEIVER_ZERO_ADDRESS");
        require(adminFeeAccumulated >= amount, "RelayManager2: INSUFFICIENT_ADMIN_FEE");
        adminFeeAccumulated -= amount;
        wIDO.safeTransfer(receiver, amount);

        emit AdminFeeWithdraw(receiver, amount);
    }

    /**
     * @dev Withdraw gas fee accumulated
     * Only operators can call
     */
    function withdrawGasFee(
        address receiver,
        uint256 amount
    ) external onlyOperator whenNotPaused {
        require(amount > 0, "RelayManager2: RECEIVER_ZERO_ADDRESS");
        require(gasFeeAccumulated >= amount, "RelayManager2: INSUFFICIENT_GAS_FEE");
        gasFeeAccumulated -= amount;
        wIDO.safeTransfer(receiver, amount);

        emit GasFeeWithdraw(receiver, amount);
    }
}
