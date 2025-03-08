// SPDX-License-Identifier: MIT  
pragma solidity 0.8.19;  
  
/**  
 * @title MockPositionManager  
 * @notice A simplified mock of the Uniswap V3 NonfungiblePositionManager for testing  
 */  
contract MockPositionManager {  
    // Structs  
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
      
    // Storage   
    mapping(uint256 => Position) private _positions;  
    mapping(uint256 => address) private _owners;  
    mapping(uint256 => address) private _approvals;  
    mapping(address => mapping(address => bool)) private _operatorApprovals;  
    mapping(address => uint256) private _balances;  
  
    // For testing purposes  
    uint256 public collectAmount0;  
    uint256 public collectAmount1;  
      
    // Testing helpers  
    function setPosition(uint256 tokenId, Position calldata position) external {  
        _positions[tokenId] = position;  
    }  
      
    function setOwner(uint256 tokenId, address owner) external {  
        _owners[tokenId] = owner;  
        _balances[owner]++;  
    }  
      
    function setCollectAmounts(uint256 amount0, uint256 amount1) external {  
        collectAmount0 = amount0;  
        collectAmount1 = amount1;  
    }  
      
    // Interface implementation  
    function positions(uint256 tokenId) external view returns (  
        uint96 nonce,  
        address operator,  
        address token0,  
        address token1,  
        uint24 fee,  
        int24 tickLower,  
        int24 tickUpper,  
        uint128 liquidity,  
        uint256 feeGrowthInside0LastX128,  
        uint256 feeGrowthInside1LastX128,  
        uint128 tokensOwed0,  
        uint128 tokensOwed1  
    ) {  
        Position memory position = _positions[tokenId];  
        return (  
            position.nonce,  
            position.operator,  
            position.token0,  
            position.token1,  
            position.fee,  
            position.tickLower,  
            position.tickUpper,  
            position.liquidity,  
            position.feeGrowthInside0LastX128,  
            position.feeGrowthInside1LastX128,  
            position.tokensOwed0,  
            position.tokensOwed1  
        );  
    }  
      
    function ownerOf(uint256 tokenId) public view returns (address) {  
        require(_owners[tokenId] != address(0), "ERC721: owner query for nonexistent token");  
        return _owners[tokenId];  
    }  
      
    function collect(CollectParams calldata) external payable returns (uint256, uint256) {  
        return (collectAmount0, collectAmount1);  
    }  
      
    function transferFrom(address from, address to, uint256 tokenId) external {  
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");  
        _transfer(from, to, tokenId);  
    }  
      
    function safeTransferFrom(address from, address to, uint256 tokenId) external {  
        safeTransferFrom(from, to, tokenId, "");  
    }  
      
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public {  
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");  
        _safeTransfer(from, to, tokenId, _data);  
    }  
      
    function approve(address to, uint256 tokenId) external {  
        address owner = ownerOf(tokenId);  
        require(to != owner, "ERC721: approval to current owner");  
          
        require(  
            msg.sender == owner || isApprovedForAll(owner, msg.sender),  
            "ERC721: approve caller is not owner nor approved for all"  
        );  
          
        _approvals[tokenId] = to;  
    }  
      
    function getApproved(uint256 tokenId) public view returns (address) {  
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");  
        return _approvals[tokenId];  
    }  
      
    function setApprovalForAll(address operator, bool approved) external {  
        require(operator != msg.sender, "ERC721: approve to caller");  
        _operatorApprovals[msg.sender][operator] = approved;  
    }  
      
    function isApprovedForAll(address owner, address operator) public view returns (bool) {  
        return _operatorApprovals[owner][operator];  
    }  
      
    function balanceOf(address owner) external view returns (uint256) {  
        require(owner != address(0), "ERC721: balance query for the zero address");  
        return _balances[owner];  
    }  
      
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {  
        return   
            interfaceId == 0x01ffc9a7 || // ERC165  
            interfaceId == 0x80ac58cd || // ERC721  
            interfaceId == 0x5b5e139f;   // ERC721Metadata  
    }  
      
    // Internal functions  
    function _exists(uint256 tokenId) internal view returns (bool) {  
        return _owners[tokenId] != address(0);  
    }  
      
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {  
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");  
        address owner = ownerOf(tokenId);  
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));  
    }  
      
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal {  
        _transfer(from, to, tokenId);  
        // No receiver check needed for mock  
    }  
      
    function _transfer(address from, address to, uint256 tokenId) internal {  
        require(ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");  
        require(to != address(0), "ERC721: transfer to the zero address");  
          
        // Clear approvals  
        _approvals[tokenId] = address(0);  
          
        // Update balances  
        _balances[from]--;  
        _balances[to]++;  
          
        // Update owner  
        _owners[tokenId] = to;  
    }  
}  
