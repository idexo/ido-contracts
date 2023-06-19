// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "../lib/OperatorableNew.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract BaseRoyaltyNFT is ERC2771Context, ERC721Enumerable, ERC721URIStorage, IERC2981, OperatorableNew  {
    // Base token URI
    string public baseTokenURI;
    // Last token ID starting from 1
    uint256 public tokenID;
    // Royalties fee receiver address
    address public royaltiesCollector;
    // Royalties fee in Basis Points
    uint16 public royaltiesFeeBP;

    event Minted(uint256 indexed tokenId);
    event Burned(uint256 indexed tokenId);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI,
        address _royaltiesCollector,
        uint16 _royaltiesFeeBP,
        address _trustedForwarder
    ) ERC2771Context(_trustedForwarder) ERC721(_name, _symbol) {
        require(_royaltiesCollector != address(0), "INVALID_ADDRESS");
        require(_royaltiesFeeBP <= 10000, "INVALID_ROYALTIES_FEE");
        baseTokenURI = _baseTokenURI;
        royaltiesCollector = _royaltiesCollector;
        royaltiesFeeBP = _royaltiesFeeBP;
    }

    /**
     * @dev Set `baseTokenURI`
     * Only `owner` can call
     */
    function setBaseTokenURI(string memory _baseTokenURI) external onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    /**
     * @dev Set `royaltiesCollector` address
     * Only `owner` can call
     * `_royaltiesCollector` must not be zero address
     */
    function setRoyaltiesCollector(address _royaltiesCollector) external onlyOwner {
        require(_royaltiesCollector != address(0), "INVALID_ADDRESS");
        royaltiesCollector = _royaltiesCollector;
    }

    /**
     * @dev Set `royaltiesFeeBP`
     * Only `owner` can call
     * `_royaltiesFeeBP` must not be greater than 1000
     */
    function setRoyaltiesFeeBP(uint16 _royaltiesFeeBP) external onlyOperator {
        require(_royaltiesFeeBP <= 10000, "INVALID_ROYALTIES_FEE");
        royaltiesFeeBP = _royaltiesFeeBP;
    }

     /**
     * @dev Implements EIP-2981 royaltyInfo()
     * Returns the royalty collector address and the royalty fee in basis points
     */
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view override returns (address receiver, uint256 royaltyAmount) {
        receiver = royaltiesCollector;
        royaltyAmount = (_salePrice * royaltiesFeeBP) / 10000;
        return (receiver, royaltyAmount);
    }

    /**
     * @dev Mint a new token
     * Only `operator` can call
     * `_account` must not be zero address
     * `_uri` can be empty
     */
    function mint(address _account, string memory _uri) public onlyOperator {
        uint256 newTokenId = ++tokenID;
        super._mint(_account, newTokenId);
        super._setTokenURI(newTokenId, _uri);

        emit Minted(newTokenId);
    }

    /**
     * @dev Burn tokens
     * Only `operator` can call
     * `_tokenId` must be valid
     */
    function burn(uint256 _tokenId) external onlyOperator {
        _burn(_tokenId);
    }

    function supportsInterface(bytes4 _interfaceId) public view virtual override(AccessControl, ERC721, ERC721Enumerable, IERC165) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    /**
     * @dev Return token URI
     * Override {ERC721URIStorage:tokenURI}
     */
    function tokenURI(uint256 _tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return ERC721URIStorage.tokenURI(_tokenId);
    }

    /**
     * @dev Override {ERC721Enumerable:_beforeTokenTransfer}
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        ERC721Enumerable._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    /**
     * @dev Override {ERC721URIStorage:_burn}
     */
    function _burn(uint256 _tokenId) internal override(ERC721, ERC721URIStorage) {
        ERC721URIStorage._burn(_tokenId);

        emit Burned(_tokenId);
    }

    /**
     * @dev Return base URI
     * Override {ERC721:_baseURI}
     */
    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    /// @notice Overrides _msgSender() function from Context.sol
    /// @return address The current execution context's sender address
    function _msgSender() internal view override(Context, ERC2771Context) returns (address){
        return ERC2771Context._msgSender();
    }

    /// @notice Overrides _msgData() function from Context.sol
    /// @return address The current execution context's data
    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata){
        return ERC2771Context._msgData();
    }
}
