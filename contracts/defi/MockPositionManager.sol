pragma solidity 0.8.19;  
  
contract MockPositionManager {  
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
      
    struct CollectParams {  
        uint256 tokenId;  
        address recipient;  
        uint128 amount0Max;  
        uint128 amount1Max;  
    }  
      
    mapping(uint256 => Position) private _positions;  
    mapping(uint256 => address) private _owners;  
    mapping(uint256 => address) private _approvals;  
    mapping(address => mapping(address => bool)) private _operatorApprovals;  
      
    uint256 private _collectAmount0;  
    uint256 private _collectAmount1;  
      
    // For testing - set a position  
    function setPosition(uint256 tokenId, Position calldata position) external {  
        _positions[tokenId] = position;  
    }  
      
    // For testing - set an owner  
    function setOwner(uint256 tokenId, address owner) external {  
        _owners[tokenId] = owner;  
    }  
      
    // For testing - set collect amounts  
    function setCollectAmounts(uint256 amount0, uint256 amount1) external {  
        _collectAmount0 = amount0;  
        _collectAmount1 = amount1;  
    }  
      
    // Uniswap V3 Position Manager functions  
    function positions(uint256 tokenId) external view returns (Position memory) {  
        return _positions[tokenId];  
    }  
      
    function ownerOf(uint256 tokenId) external view returns (address) {  
        return _owners[tokenId];  
    }  
      
    function collect(CollectParams calldata params) external payable returns (uint256, uint256) {  
        return (_collectAmount0, _collectAmount1);  
    }  
      
    function transferFrom(address from, address to, uint256 tokenId) external {  
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");  
        _owners[tokenId] = to;  
    }  
      
    function safeTransferFrom(address from, address to, uint256 tokenId) external {  
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");  
        _owners[tokenId] = to;  
    }  
      
    function approve(address to, uint256 tokenId) external {  
        address owner = _owners[tokenId];  
        require(msg.sender == owner || _operatorApprovals[owner][msg.sender], "Not authorized");  
        _approvals[tokenId] = to;  
    }  
      
    function getApproved(uint256 tokenId) external view returns (address) {  
        return _approvals[tokenId];  
    }  
      
    function setApprovalForAll(address operator, bool approved) external {  
        _operatorApprovals[msg.sender][operator] = approved;  
    }  
      
    function isApprovedForAll(address owner, address operator) external view returns (bool) {  
        return _operatorApprovals[owner][operator];  
    }  
      
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {  
        address owner = _owners[tokenId];  
        return (  
            spender == owner ||  
            spender == _approvals[tokenId] ||  
            _operatorApprovals[owner][spender]  
        );  
    }  
}  
