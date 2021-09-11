// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./libs/BaseRelayRecipient.sol";

contract LiquidityPoolManager is Pausable, AccessControl, BaseRelayRecipient, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // The contract owner address
    address public owner;
    // Proposed contract new owner address
    address public newOwner;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    // IDO token address
    IERC20 ido;

    uint256 public baseGas;

    uint256 public adminFee; // bps
    uint256 public adminFeeAccumulated;
    uint256 public gasFeeAccumulated;

    // Token transfer caps
    uint256 public minDepositCap;
    uint256 public maxDepositCap;
    // Liquidity amount in $IDO
    uint256 public liquidity;

    mapping(address => uint256) public liquidityProviders;
    // Transfer nonce
    mapping(address => uint256) public nonces;
    // Transfer hash processed status
    mapping(bytes32 => bool) public processedHashes;

    struct PermitRequest {
        uint256 nonce;
        uint256 expiry;
        bool allowed;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // Events
    event Deposited(address indexed from, address indexed receiver, uint256 toChainId, uint256 amount, uint256 nonce);
    event Sent(address indexed receiver, uint256 indexed amount, uint256 indexed transferredAmount, bytes32 depositHash);
    event AdminFeeChanged(uint256 indexed AdminFee);
    event TrustedForwarderChanged(address indexed TrustedForwarder);
    event LiquidityAdded(address indexed sender, uint256 amount);
    event LiquidityRemoved(address indexed sender, uint256 amount);
    event EthReceived(address indexed sender, uint256 amount);

    constructor(
        IERC20 _ido,
        address _trustedForwarder,
        uint256 _adminFee
    ) {
        require(_trustedForwarder != address(0), "LiquidityPoolManager: TRUSTED_FORWARDER_ZERO_ADDRESS");
        require(_adminFee != 0, "LiquidityPoolManager: ADMIN_FEE_INVALID");
        address sender = _msgSender();
        ido = _ido;
        owner = sender;
        trustedForwarder = _trustedForwarder;
        adminFee = _adminFee;
        baseGas = 21000; // default block gas limit

        _setupRole(DEFAULT_ADMIN_ROLE, sender);
        _setupRole(OPERATOR_ROLE, sender);

        emit OwnershipTransferred(address(0), sender);
    }

    receive() external payable {
        emit EthReceived(_msgSender(), msg.value);
    }

    // TODO check whenNotPaused and whenPaused for function calls

    /**************************|
    |          Setters         |
    |_________________________*/

    /**
     * @dev Set admin fee bps
     * Only `owner` can call
     */
    function setAdminFee(uint256 newAdminFee) external onlyOwner whenNotPaused {
        require(newAdminFee != 0, "LiquidityPoolManager: ADMIN_FEE_INVALID");
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
     * @dev Set trustedForwarder address
     * Only `owner` can call
     */
    function setTrustedForwarder(address newTrustedForwarder) external onlyOwner {
        require(newTrustedForwarder != address(0), "LiquidityPoolManager: TRUSTED_FORWARDER_ZERO_ADDRESS");
        trustedForwarder = newTrustedForwarder;

        emit TrustedForwarderChanged(newTrustedForwarder);
    }

    /**
     * @dev Set deposit cap limits
     * Only `owner` can call
     */
    function setDepositCap(uint256 _minDepositCap, uint256 _maxDepositCap) external onlyOwner {
        require(_minDepositCap < _maxDepositCap, "LiquidityPoolManager: DEPOSIT_CAP_INVALID");
        minDepositCap = _minDepositCap;
        maxDepositCap = _maxDepositCap;
    }

    /****************************|
    |          Ownership         |
    |___________________________*/

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner == _msgSender(), "LiquidityPoolManager: CALLER_NO_OWNER");
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
        require(_newOwner != address(0), "LiquidityPoolManager: INVALID_ADDRESS");
        require(_newOwner != owner, "LiquidityPoolManager: OWNERSHIP_SELF_TRANSFER");
        newOwner = _newOwner;
    }

    /**
     * @dev The new owner accept an ownership transfer.
     */
    function acceptOwnership() external {
        require(_msgSender() == newOwner, "LiquidityPoolManager: CALLER_NO_NEW_OWNER");
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
        require(hasRole(OPERATOR_ROLE, _msgSender()), "LiquidityPoolManager: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     */
    function addOperator(address account) public onlyOwner {
        require(!hasRole(OPERATOR_ROLE, account), "LiquidityPoolManager: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     */
    function removeOperator(address account) public onlyOwner {
        require(hasRole(OPERATOR_ROLE, account), "LiquidityPoolManager: NO_OPERATOR_ROLE");
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

    /****************************|
    |          Liquidity         |
    |___________________________*/

    /**
     * @dev Add liquidity to the liquidity pool contract
     */
    function addLiquidity(uint256 amount) external whenNotPaused nonReentrant {
        require(amount != 0, "LiquidityPoolManager: LIQUIDITY_AMOUNT_INVALID");
        address sender = _msgSender();
        liquidityProviders[sender] += amount;
        liquidity += amount;
        ido.safeTransferFrom(sender, address(this), amount);

        emit LiquidityAdded(sender, amount);
    }

    /**
     * @dev Remove liquidity from the liquidity pool contract
     */
    function removeLiquidity(uint256 amount) external whenNotPaused nonReentrant {
        require(amount != 0, "LiquidityPoolManager: LIQUIDITY_AMOUNT_INVALID");
        address sender = _msgSender();
        require(liquidityProviders[sender] >= amount, "LiquidityPoolManager: INSUFFICIENT_FUNDS");
        require(liquidity >= amount, "LiquidityPoolManager: INSUFFICIENT_LIQUIDITY");
        liquidityProviders[sender] -= amount;
        ido.safeTransfer(sender, amount);

        emit LiquidityRemoved(sender, amount);
    }

    /***************************|
    |          Transfer         |
    |__________________________*/

    /**
     * @dev Deposit funds to the liquidity pool contract for cross-chain transfer
     */
    function deposit(
        address receiver,
        uint256 amount,
        uint256 toChainId
    ) external whenNotPaused {
        require(minDepositCap <= amount && amount <= maxDepositCap, "LiquidityPoolManager: DEPOSIT_AMOUNT_OUT_OF_RANGE");
        require(receiver != address(0), "LiquidityPoolManager: RECEIVER_ZERO_ADDRESS");
        address sender = _msgSender();
        liquidity += amount;
        ido.safeTransferFrom(sender, address(this), amount);

        emit Deposited(sender, receiver, toChainId, amount, ++nonces[sender]);
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
        require(receiver != address(0), "LiquidityPoolManager: RECEIVER_ZERO_ADDRESS");
        require(minDepositCap <= amount && amount <= maxDepositCap, "LiquidityPoolManager: SEND_AMOUNT_OUT_OF_RANGE");
        require(!processedHashes[depositHash], "LiquidityPoolManager: ALREADY_PROCESSED");
        // TODO check that liquidity + gasFeeAccumulated + adminFeeAccumulate
        require(liquidity >= amount, "LiquidityPoolManager: INSUFFICIENT_LIQUIDITY");
        // Decrease liquidity
        liquidity -= amount;
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

        ido.safeTransfer(receiver, amountToTransfer);

        emit Sent(receiver, amount, amountToTransfer, depositHash);
    }

    // TODO check again withdraw $IDO, gasFeeAccumulated, adminFeeAccumulated

    /**
     * Return the sender of this call.
     * If the call came through our trusted forwarder, return the original sender.
     * otherwise, return `msg.sender`.
     * should be used in the contract anywhere instead of `msg.sender`
     */
    function _msgSender() internal virtual override(BaseRelayRecipient, Context) view returns (address) {
        return BaseRelayRecipient._msgSender();
    }
}
