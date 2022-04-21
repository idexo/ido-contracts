// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "../../lib/Error.sol";
import "../../lib/Operatorable.sol";

contract BaseRoyaltyNFT is ERC721Enumerable, ERC721URIStorage, Operatorable {
    // Base token URI
    string public baseTokenURI;
    // Last token ID starting from 1
    uint256 public tokenID;
    // Royalties fee receiver address
    address public royaltiesCollector;

    event LogMinted(uint256 indexed tokenId);
    event LogBurnt(uint256 indexed tokenId);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI,
        address _royaltiesCollector
    ) ERC721(_name, _symbol) {
        if (_royaltiesCollector == address(0)) revert InvalidAddress();
        baseTokenURI = _baseTokenURI;
        royaltiesCollector = _royaltiesCollector;
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
        if (_royaltiesCollector == address(0)) revert InvalidAddress();
        royaltiesCollector = _royaltiesCollector;
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

        emit LogMinted(newTokenId);
    }

    /**
     * @dev Burn tokens
     * Only `operator` can call
     * `_tokenId` must be valid
     */
    function burn(uint256 _tokenId) external onlyOperator {
        _burn(_tokenId);
    }

    function supportsInterface(bytes4 _interfaceId) public view virtual override(AccessControl, ERC721, ERC721Enumerable) returns (bool) {
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
        address _from,
        address _to,
        uint256 _tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        ERC721Enumerable._beforeTokenTransfer(_from, _to, _tokenId);
    }

    /**
     * @dev Override {ERC721URIStorage:_burn}
     */
    function _burn(uint256 _tokenId) internal override(ERC721, ERC721URIStorage) {
        ERC721URIStorage._burn(_tokenId);

        emit LogBurnt(_tokenId);
    }

    /**
     * @dev Return base URI
     * Override {ERC721:_baseURI}
     */
    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }
}
