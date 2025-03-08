// SPDX-License-Identifier: MIT  
pragma solidity ^0.8.19;  
  
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";  
import "@openzeppelin/contracts/access/Ownable.sol";  
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";  
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";  
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";  
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";  
  
interface INonfungiblePositionManager {  
    struct MintParams {  
        address token0;  
        address token1;  
        uint24 fee;  
        int24 tickLower;  
        int24 tickUpper;  
        uint256 amount0Desired;  
        uint256 amount1Desired;  
        uint256 amount0Min;  
        uint256 amount1Min;  
        address recipient;  
        uint256 deadline;  
    }  
  
    struct CollectParams {  
        uint256 tokenId;  
        address recipient;  
        uint128 amount0Max;  
        uint128 amount1Max;  
    }  
  
    struct Position {  
        uint96 nonce;  
        address operator;  
        address token0;  
        address token1;  
        uint24 fee;  
        int24 tickLower;  
        int24 tickUpper;  
        uint128 liquidity;  
        uint256 feeGrowthInside0LastX128;  
        uint256 feeGrowthInside1LastX128;  
        uint128 tokensOwed0;  
        uint128 tokensOwed1;  
    }  
  
    function positions(uint256 tokenId) external view returns (Position memory);  
      
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);  
      
    function transferFrom(address from, address to, uint256 tokenId) external;  
      
    function safeTransferFrom(address from, address to, uint256 tokenId) external;  
}  
  
/**  
 * @title UniV3PositionLocker  
 * @notice This contract allows users to lock their Uniswap V3 LP Position NFTs for a set period  
 * while still being able to collect trading fees.  
 * @dev Implements IERC721Receiver to receive the NFTs.  
 */  
contract UniV3PositionLocker is IERC721Receiver, Ownable, ReentrancyGuard {  
    using SafeERC20 for IERC20;  
  
    // Position Manager contract  
    INonfungiblePositionManager public positionManager;  
      
    // Lock duration in seconds  
    uint256 public immutable lockDuration;  
      
    // Timestamp when the contract was deployed  
    uint256 public immutable deploymentTime;  
      
    // Timestamp when the lock period ends  
    uint256 public immutable lockEndTimestamp;  
  
    // Struct to store locked position information  
    struct LockedPosition {  
        address owner;      // Original owner of the position  
        uint256 tokenId;    // Uniswap V3 position token ID  
        uint256 lockedAt;   // When the position was locked  
        bool isWithdrawn;   // Whether the position has been withdrawn  
    }  
  
    // Mapping from lock ID to locked position  
    mapping(uint256 => LockedPosition) public lockedPositions;  
      
    // Counter for generating unique lock IDs  
    uint256 private _nextLockId = 1;  
      
    // Mapping from token ID to lock ID for quick lookups  
    mapping(uint256 => uint256) public tokenIdToLockId;  
      
    // Events  
    event PositionLocked(uint256 indexed lockId, uint256 indexed tokenId, address indexed owner, uint256 lockedAt);  
    event PositionUnlocked(uint256 indexed lockId, uint256 indexed tokenId, address indexed recipient, uint256 unlockedAt);  
    event FeesCollected(uint256 indexed lockId, uint256 indexed tokenId, address indexed recipient, uint256 amount0, uint256 amount1);  
    event EmergencyWithdraw(uint256 indexed lockId, uint256 indexed tokenId, address indexed recipient);  
  
    /**  
     * @dev Constructor initializes the contract with position manager address and lock duration  
     * @param _positionManager Address of the Uniswap V3 NonfungiblePositionManager  
     * @param _lockDuration Duration in seconds for which positions will be locked  
     */  
    constructor(address _positionManager, uint256 _lockDuration) {  
        require(_positionManager != address(0), "Invalid position manager address");  
        require(_lockDuration > 0, "Lock duration must be positive");  
          
        positionManager = INonfungiblePositionManager(_positionManager);  
        lockDuration = _lockDuration;  
        deploymentTime = block.timestamp;  
        lockEndTimestamp = deploymentTime + _lockDuration;  
    }  
  
    /**  
     * @dev Locks a Uniswap V3 LP Position NFT in the contract  
     * @param tokenId The token ID of the position to lock  
     * @return lockId The unique identifier for the locked position  
     */  
    function lockPosition(uint256 tokenId) external nonReentrant returns (uint256 lockId) {  
        require(tokenId > 0, "Invalid token ID");  
        require(tokenIdToLockId[tokenId] == 0, "Token already locked");  
          
        // Transfer NFT from sender to this contract  
        positionManager.transferFrom(msg.sender, address(this), tokenId);  
          
        // Create a new lock ID and store position details  
        lockId = _nextLockId++;  
          
        lockedPositions[lockId] = LockedPosition({  
            owner: msg.sender,  
            tokenId: tokenId,  
            lockedAt: block.timestamp,  
            isWithdrawn: false  
        });  
          
        tokenIdToLockId[tokenId] = lockId;  
          
        emit PositionLocked(lockId, tokenId, msg.sender, block.timestamp);  
          
        return lockId;  
    }  
      
    /**  
     * @dev Unlocks a position and returns it to the owner after lock period ends  
     * @param lockId The lock ID of the position to unlock  
     */  
    function unlockPosition(uint256 lockId) external nonReentrant {  
        require(block.timestamp >= lockEndTimestamp, "Lock period not ended yet");  
          
        LockedPosition storage position = lockedPositions[lockId];  
        require(position.owner == msg.sender, "Not the position owner");  
        require(!position.isWithdrawn, "Position already withdrawn");  
          
        // Mark as withdrawn  
        position.isWithdrawn = true;  
          
        // Transfer NFT back to owner  
        positionManager.safeTransferFrom(address(this), msg.sender, position.tokenId);  
          
        emit PositionUnlocked(lockId, position.tokenId, msg.sender, block.timestamp);  
    }  
      
    /**  
     * @dev Collects fees from a locked position  
     * @param lockId The lock ID of the position  
     * @param recipient Address to receive the collected fees  
     * @param amount0Max Maximum amount of token0 to collect  
     * @param amount1Max Maximum amount of token1 to collect  
     * @return amount0 Amount of token0 collected  
     * @return amount1 Amount of token1 collected  
     */  
    function collectFees(  
        uint256 lockId,  
        address recipient,  
        uint128 amount0Max,  
        uint128 amount1Max  
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {  
        LockedPosition storage position = lockedPositions[lockId];  
        require(position.owner == msg.sender, "Not the position owner");  
        require(!position.isWithdrawn, "Position already withdrawn");  
        require(recipient != address(0), "Invalid recipient");  
          
        // Collect the fees  
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({  
            tokenId: position.tokenId,  
            recipient: recipient,  
            amount0Max: amount0Max,  
            amount1Max: amount1Max  
        });  
          
        (amount0, amount1) = positionManager.collect(params);  
          
        emit FeesCollected(lockId, position.tokenId, recipient, amount0, amount1);  
          
        return (amount0, amount1);  
    }  
      
    /**  
     * @dev Returns information about a locked position  
     * @param lockId The lock ID of the position  
     * @return owner The original owner of the position  
     * @return tokenId The Uniswap V3 position token ID  
     * @return lockedAt When the position was locked  
     * @return isWithdrawn Whether the position has been withdrawn  
     */  
    function getLockedPosition(uint256 lockId) external view returns (  
        address owner,  
        uint256 tokenId,  
        uint256 lockedAt,  
        bool isWithdrawn  
    ) {  
        LockedPosition storage position = lockedPositions[lockId];  
        return (  
            position.owner,  
            position.tokenId,  
            position.lockedAt,  
            position.isWithdrawn  
        );  
    }  
      
    /**  
     * @dev Returns detailed information about a Uniswap V3 position  
     * @param tokenId The token ID of the position  
     * @return position Detailed position information including liquidity, fees, etc.  
     */  
    function getPositionDetails(uint256 tokenId) external view returns (INonfungiblePositionManager.Position memory) {  
        return positionManager.positions(tokenId);  
    }  
      
    /**  
     * @dev Retrieves the lock ID for a given token ID  
     * @param tokenId The token ID to query  
     * @return The corresponding lock ID, or 0 if not locked  
     */  
    function getLockIdForToken(uint256 tokenId) external view returns (uint256) {  
        return tokenIdToLockId[tokenId];  
    }  
      
    /**  
     * @dev Required by IERC721Receiver  
     */  
    function onERC721Received(  
        address,  
        address,  
        uint256,  
        bytes calldata  
    ) external pure override returns (bytes4) {  
        return IERC721Receiver.onERC721Received.selector;  
    }  
      
    /**  
     * @dev Allows the contract to receive ETH  
     */  
    receive() external payable {}  
}  