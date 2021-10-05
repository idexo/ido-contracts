// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IStakePoolSimple.sol";
import "../interfaces/IStakeTokenSimple.sol";

contract StakePoolSimple is IStakePoolSimple, AccessControl, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    // Minimum stake amount
    uint256 public constant minStakeAmount = 2500 * 1e18;

    // StakeTokenSimple NFT
    IStakeTokenSimple stakeTokenSimple;
    // IDO token
    IERC20 public ido;
    // USDT token
    IERC20 public usdt;

    event Deposited(address indexed account, uint256 indexed stakeId, uint256 amount);
    event Withdrawn(address indexed account, uint256 indexed stakeId, uint256 amount);
    event Swept(address indexed operator, address token, address indexed to, uint256 amount);

    constructor(
        IStakeTokenSimple stakeTokenSimple_,
        IERC20 ido_,
        IERC20 usdt_
    ) {
        stakeTokenSimple = stakeTokenSimple_;
        ido = ido_;
        usdt = usdt_;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
    }

    /**
     * @dev Override supportInterface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /***********************|
    |          Role         |
    |______________________*/

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "StakePoolSimple: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     */
    function addOperator(address account) public override onlyOwner {
        // Check if `account` already has operator role
        require(!hasRole(OPERATOR_ROLE, account), "StakePoolSimple: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     */
    function removeOperator(address account) public override onlyOwner {
        // Check if `account` has operator role
        require(hasRole(OPERATOR_ROLE, account), "StakePoolSimple: NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     */
    function checkOperator(address account) public override view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /***************************|
    |          Pausable         |
    |__________________________*/

    /**
     * @dev Pause the pool
     */
    function pause() external onlyOperator {
        super._pause();
    }

    /**
     * @dev Unpause the pool
     */
    function unpause() external onlyOperator {
        super._unpause();
    }

    /************************|
    |          Stake         |
    |_______________________*/

    /**
     * @dev Deposit stake to the pool.
     *
     * - `amount` >= `minStakeAmount`
     */
    function deposit(uint256 amount) external override whenNotPaused {
        require(amount >= minStakeAmount, "StakePoolSimple: UNDER_MINIMUM_STAKE_AMOUNT");
        _deposit(_msgSender(), amount);
    }

    /**
     * @dev Withdraw stake from the pool.
     *
     * If `amount` is less than amount of the stake, cut down the stake amount.
     * If `amount` is equal to amount of the stake, burn the stake.
     *
     * - `amount` must not be zero
     * - `stakeId` should be valid
     */
    function withdraw(
        uint256 stakeId,
        uint256 amount
    ) external override whenNotPaused {
        require(amount > 0, "StakePoolSimple: WITHDRAW_AMOUNT_INVALID");
        _withdraw(_msgSender(), stakeId, amount);
    }

    /**
     * @dev Deposit stake to the pool.
     * Mint a new StakeToken.
     * Transfer `amount` of IDO from `account` to the pool.
     * Zero account check for `account` happen in {ERC721}.
     */
    function _deposit(
        address account,
        uint256 amount
    ) private nonReentrant {
        uint256 stakeId = stakeTokenSimple.create(account, amount, block.timestamp);
        ido.safeTransferFrom(account, address(this), amount);

        emit Deposited(account, stakeId, amount);
    }

    /**
     * @dev If `amount` is less than amount of the stake, cut down the stake amount.
     * If `amount` is equal to amount of the stake, burn the stake.
     * Transfer `withdrawAmount` of IDO from the pool to `account`.
     *
     * - `amount` must not be zero
     * - `stakeId` should be valid
     * - `account` must be owner of `stakeId`
     */
    function _withdraw(
        address account,
        uint256 stakeId,
        uint256 withdrawAmount
    ) private nonReentrant {
        require(stakeTokenSimple.ownerOf(stakeId) == account, "StakePoolSimple: NO_STAKE_OWNER");
        stakeTokenSimple.decreaseStakeAmount(stakeId, withdrawAmount);
        ido.safeTransfer(account, withdrawAmount);

        emit Withdrawn(account, stakeId, withdrawAmount);
    }

    /**
     * @dev Withdraw funds from the pool
     * Operators only can call
     *
     * - `token_` must not be zero address
     * - `amount` must not be zero
     */
    function sweep(
        address token_,
        address to,
        uint256 amount
    ) public onlyOwner {
        require(token_ != address(0), "StakePoolSimple: TOKEN_ADDRESS_INVALID");
        require(amount > 0, "StakePoolSimple: AMOUNT_INVALID");
        IERC20 token = IERC20(token_);
        // balance check is being done in {ERC20}
        token.safeTransfer(to, amount);
        emit Swept(_msgSender(), token_, to, amount);
    }
}
