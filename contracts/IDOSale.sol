// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * Users can purchase tokens after sale started and claim after sale ended
 */

contract IDOSale is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    // Contract owner address
    address public owner;
    // Proposed new contract owner address
    address public newOwner;
    // user address => whitelisted status
    mapping(address => bool) public whitelist;
    // user address => purchased token amount
    mapping(address => uint256) public purchasedAmounts;
    // user address => claimed token amount
    mapping(address => uint256) public claimedAmounts;
    // Once-whitelisted user address array, even removed users still remain
    address[] private _whitelistedUsers;
    // IDO token price
    uint256 public idoPrice;
    // IDO token address
    IERC20 public ido;
    // USDT address
    IERC20 public purchaseToken;
    // The cap amount each user can purchase IDO up to
    uint256 public purchaseCap;
    // The total purchased amount
    uint256 public totalPurchasedAmount;

    // Date timestamp when token sale start
    uint256 public startTime;
    // Date timestamp when token sale ends
    uint256 public endTime;

    // Used for returning purchase history
    struct Purchase {
        address account;
        uint256 amount;
    }
    // ERC20Permit
    struct PermitRequest {
        uint256 nonce;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event IdoPriceChanged(uint256 idoPrice);
    event PurchaseCapChanged(uint256 purchaseCap);
    event WhitelistAdded(address indexed account);
    event WhitelistRemoved(address indexed account);
    event Deposited(address indexed sender, uint256 amount);
    event Purchased(address indexed sender, uint256 amount);
    event Claimed(address indexed sender, uint256 amount);
    event Swept(address indexed sender, uint256 amount);

    constructor(
        IERC20 _ido,
        IERC20 _purchaseToken,
        uint256 _idoPrice,
        uint256 _purchaseCap,
        uint256 _startTime,
        uint256 _endTime
    ) {
        require(address(_ido) != address(0), "IDOSale: IDO_ADDRESS_INVALID");
        require(address(_purchaseToken) != address(0), "IDOSale: PURCHASE_TOKEN_ADDRESS_INVALID");
        require(_idoPrice > 0, "IDOSale: TOKEN_PRICE_INVALID");
        require(_purchaseCap > 0, "IDOSale: PURCHASE_CAP_INVALID");
        require(block.timestamp <= _startTime && _startTime < _endTime, "IDOSale: TIMESTAMP_INVALID");

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());

        ido = _ido;
        purchaseToken = _purchaseToken;
        owner = _msgSender();
        idoPrice = _idoPrice;
        purchaseCap = _purchaseCap;
        startTime = _startTime;
        endTime = _endTime;

        emit OwnershipTransferred(address(0), _msgSender());
    }

    /**************************|
    |          Setters         |
    |_________________________*/

    /**
     * @dev Set ido token price in purchaseToken
     */
    function setIdoPrice(uint256 _idoPrice) external onlyOwner {
        idoPrice = _idoPrice;

        emit IdoPriceChanged(_idoPrice);
    }

    /**
     * @dev Set purchase cap for each user
     */
    function setPurchaseCap(uint256 _purchaseCap) external onlyOwner {
        purchaseCap = _purchaseCap;

        emit PurchaseCapChanged(_purchaseCap);
    }

    /****************************|
    |          Ownership         |
    |___________________________*/

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner == _msgSender(), "IDOSale: CALLER_NO_OWNER");
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
     *
     * @param _newOwner new contract owner.
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "IDOSale: INVALID_ADDRESS");
        require(_newOwner != owner, "IDOSale: OWNERSHIP_SELF_TRANSFER");
        newOwner = _newOwner;
    }

    /**
     * @dev The new owner accept an ownership transfer.
     */
    function acceptOwnership() external {
        require(_msgSender() == newOwner, "IDOSale: CALLER_NO_NEW_OWNER");
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
        require(hasRole(OPERATOR_ROLE, _msgSender()), "IDOSale: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     * @param account address
     */
    function addOperator(address account) public onlyOwner {
        require(!hasRole(OPERATOR_ROLE, account), "IDOSale: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     * @param account address
     */
    function removeOperator(address account) public onlyOwner {
        require(hasRole(OPERATOR_ROLE, account), "IDOSale: NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     * @param account address
     */
    function checkOperator(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /***************************|
    |          Pausable         |
    |__________________________*/

    /**
     * @dev Pause the sale
     */
    function pause() external onlyOperator {
        super._pause();
    }

    /**
     * @dev Unpause the sale
     */
    function unpause() external onlyOperator {
        super._unpause();
    }


    /****************************|
    |          Whitelist         |
    |___________________________*/

    /**
     * @dev Return whitelisted users
     * The result array can include zero address
     */
    function whitelistedUsers() external view returns (address[] memory) {
        address[] memory __whitelistedUsers = new address[](_whitelistedUsers.length);
        for (uint256 i = 0; i < _whitelistedUsers.length; i++) {
            if (!whitelist[_whitelistedUsers[i]]) {
                continue;
            }
            __whitelistedUsers[i] = _whitelistedUsers[i];
        }

        return __whitelistedUsers;
    }

    /**
     * @dev Add wallet to whitelist
     * If wallet is added, removed and added to whitelist, the account is repeated
     */
    function addWhitelist(address[] memory accounts) external onlyOperator whenNotPaused {
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "IDOSale: ZERO_ADDRESS");
            if (!whitelist[accounts[i]]) {
                whitelist[accounts[i]] = true;
                _whitelistedUsers.push(accounts[i]);

                emit WhitelistAdded(accounts[i]);
            }
        }
    }

    /**
     * @dev Remove wallet from whitelist
     * Removed wallets still remain in `_whitelistedUsers` array
     */
    function removeWhitelist(address[] memory accounts) external onlyOperator whenNotPaused {
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "IDOSale: ZERO_ADDRESS");
            if (whitelist[accounts[i]]) {
                whitelist[accounts[i]] = false;

                emit WhitelistRemoved(accounts[i]);
            }
        }
    }

    /***************************|
    |          Purchase         |
    |__________________________*/

    /**
     * @dev Return purchase history (wallet address, amount)
     * The result array can include zero amount item
     */
    function purchaseHistory() external view returns (Purchase[] memory) {
        Purchase[] memory purchases = new Purchase[](_whitelistedUsers.length);
        for (uint256 i = 0; i < _whitelistedUsers.length; i++) {
            purchases[i].account = _whitelistedUsers[i];
            purchases[i].amount = purchasedAmounts[_whitelistedUsers[i]];
        }

        return purchases;
    }

    /**
     * @dev Deposit IDO token to the sale contract
     */
    function depositTokens(uint256 amount) external onlyOperator whenNotPaused {
        require(amount > 0, "IDOSale: DEPOSIT_AMOUNT_INVALID");
        ido.safeTransferFrom(_msgSender(), address(this), amount);

        emit Deposited(_msgSender(), amount);
    }

    /**
     * @dev Permit and deposit IDO token to the sale contract
     * If token does not have `permit` function, this function does not work
     */
    function permitAndDepositTokens(
        uint256 amount,
        PermitRequest calldata permitOptions
    ) external onlyOperator whenNotPaused {
        require(amount > 0, "IDOSale: DEPOSIT_AMOUNT_INVALID");

        // Permit
        IERC20Permit(address(ido)).permit(_msgSender(), address(this), amount, permitOptions.deadline, permitOptions.v, permitOptions.r, permitOptions.s);
        ido.safeTransferFrom(_msgSender(), address(this), amount);

        emit Deposited(_msgSender(), amount);
    }

    /**
     * @dev Purchase IDO token
     * Only whitelisted users can purchase within `purchcaseCap` amount
     */
    function purchase(uint256 amount) external nonReentrant whenNotPaused {
        require(startTime <= block.timestamp, "IDOSale: SALE_NOT_STARTED");
        require(block.timestamp < endTime, "IDOSale: SALE_ALREADY_ENDED");
        require(amount > 0, "IDOSale: PURCHASE_AMOUNT_INVALID");
        require(whitelist[_msgSender()], "IDOSale: CALLER_NO_WHITELIST");
        require(purchasedAmounts[_msgSender()] + amount <= purchaseCap, "IDOSale: PURCHASE_CAP_EXCEEDED");
        uint256 idoBalance = ido.balanceOf(address(this));
        require(totalPurchasedAmount + amount <= idoBalance, "IDOSale: INSUFFICIENT_SELL_BALANCE");
        uint256 purchaseTokenAmount = amount * idoPrice / (10 ** 18);
        require(purchaseTokenAmount <= purchaseToken.balanceOf(_msgSender()), "IDOSale: INSUFFICIENT_FUNDS");

        purchasedAmounts[_msgSender()] += amount;
        totalPurchasedAmount += amount;
        purchaseToken.safeTransferFrom(_msgSender(), address(this), purchaseTokenAmount);

        emit Purchased(_msgSender(), amount);
    }

    /**
     * @dev Purchase IDO token
     * Only whitelisted users can purchase within `purchcaseCap` amount
     * If `purchaseToken` does not have `permit` function, this function does not work
     */
    function permitAndPurchase(
        uint256 amount,
        PermitRequest calldata permitOptions
    ) external nonReentrant whenNotPaused {
        require(startTime <= block.timestamp, "IDOSale: SALE_NOT_STARTED");
        require(block.timestamp < endTime, "IDOSale: SALE_ALREADY_ENDED");
        require(amount > 0, "IDOSale: PURCHASE_AMOUNT_INVALID");
        require(whitelist[_msgSender()], "IDOSale: CALLER_NO_WHITELIST");
        require(purchasedAmounts[_msgSender()] + amount <= purchaseCap, "IDOSale: PURCHASE_CAP_EXCEEDED");
        uint256 idoBalance = ido.balanceOf(address(this));
        require(totalPurchasedAmount + amount <= idoBalance, "IDOSale: INSUFFICIENT_SELL_BALANCE");
        uint256 purchaseTokenAmount = amount * idoPrice / (10 ** 18);
        require(purchaseTokenAmount <= purchaseToken.balanceOf(_msgSender()), "IDOSale: INSUFFICIENT_FUNDS");

        purchasedAmounts[_msgSender()] += amount;
        totalPurchasedAmount += amount;
        IERC20Permit(address(purchaseToken)).permit(_msgSender(), address(this), amount, permitOptions.deadline, permitOptions.v, permitOptions.r, permitOptions.s);
        purchaseToken.safeTransferFrom(_msgSender(), address(this), purchaseTokenAmount);

        emit Purchased(_msgSender(), amount);
    }

    /************************|
    |          Claim         |
    |_______________________*/

    /**
     * @dev Users claim purchased tokens after token sale ended
     */
    function claim(uint256 amount) external nonReentrant whenNotPaused {
        require(endTime <= block.timestamp, "IDOSale: SALE_NOT_ENDED");
        require(amount > 0, "IDOSale: CLAIM_AMOUNT_INVALID");
        require(claimedAmounts[_msgSender()] + amount <= purchasedAmounts[_msgSender()], "IDOSale: CLAIM_AMOUNT_EXCEEDED");

        claimedAmounts[_msgSender()] += amount;
        ido.safeTransfer(_msgSender(), amount);

        emit Claimed(_msgSender(), amount);
    }

    /**
     * @dev `Operator` sweeps `purchaseToken` from the sale contract to `to` address
     */
    function sweep(address to) external onlyOwner {
        require(to != address(0), "IDOSale: ADDRESS_INVALID");
        require(endTime <= block.timestamp, "IDOSale: SALE_NOT_ENDED");
        uint256 bal = purchaseToken.balanceOf(address(this));
        purchaseToken.safeTransfer(to, bal);

        emit Swept(to, bal);
    }
}
