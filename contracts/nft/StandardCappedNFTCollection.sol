// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../lib/Operatorable.sol";

contract StandardCappedNFTCollection is ERC721URIStorage, Operatorable, ReentrancyGuard {
    using SafeMath for uint256;

    //Last stake token id, start from 1
    uint256 public tokenIds;

    //NFT Base URI
    string public baseURI;

    //NFT Collection Description
    string public collectionDescription;

    //cap on # of nfts in collection
    uint256 private _cap;

    //Collection wallet => nft id
    mapping(address => uint256[]) public collectionIds;

    event NFTCreated(uint256 indexed nftId, address indexed account);
    

    constructor(
        string memory collectionName,
        string memory collectionSymbol,
        string memory collectionBaseURI,
        uint256 cap
    ) ERC721(collectionName, collectionSymbol) {
        require(cap > 0, "StandardCappedNFTCollection#constructor: CAP_MUST_BE_GREATER_THAN_0");
        baseURI = collectionBaseURI;
        _cap = cap;
    }

    /**
     * @dev Override supportInterface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

         /**
     * @dev Get collection token id array owned by wallet address.
     * @param account address
     */
    function getCollectionIds(address account) public view returns (uint256[] memory) {
        return collectionIds[account];
    }

    /**********************|
    |          URI         |
    |_____________________*/

    /**
     * @dev Set token URI
     * Only `operator` can call
     *
     * - `tokenId` must exist, see {ERC721URIStorage:_setTokenURI}
     */
    function setTokenURI(uint256 tokenId, string memory _tokenURI) public onlyOperator {
        super._setTokenURI(tokenId, _tokenURI);
    }

    /**
     * @dev Set `baseURI`
     * Only `operator` can call
     */
    function setBaseURI(string memory baseURI_) public onlyOwner {
        baseURI = baseURI_;
    }

    /**
     * @dev Return base URI
     * Override {ERC721:_baseURI}
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**********************|
    |          Description |
    |_____________________*/

    function addDescription(string memory description) public onlyOperator {
        collectionDescription = description;
    }

    /**********************|
    |          MINT        |
    |_____________________*/

    /**
     * @dev Mint a new token.
     * @param recipient address
     */
    function mintNFT(address recipient, string memory _tokenURI) public onlyOperator returns (uint256) {
        

        tokenIds++;
        _mint(recipient, tokenIds);
        super._setTokenURI(tokenIds, _tokenURI);
        return tokenIds;
    }

     /**
     * @dev Mint multiple new tokens.
     * @param recipients array of recipient address.
     * @param tokenURIs array of token URI.
     */
    function mintBatchNFT(
        address[] memory recipients,
        string[] memory tokenURIs
    )
        public
        onlyOperator
    {
        require(recipients.length == tokenURIs.length, "StandardCappedNFTCollection#mintBatchNFT: PARAMS_LENGTH_MISMATCH");
        require(tokenIds + recipients.length <= _cap, "StandardCappedNFTCollection#mintBatchNFT: CANNOT_EXCEED_MINTING_CAP");
        for (uint256 i = 0; i < recipients.length; i++) {
            mintNFT(recipients[i], tokenURIs[i]);
        }
    }

    /**
     * @dev Check if wallet address owns any nfts in the collection.
     * @param account address
     */
    function isHolder(address account) public view returns (bool) {
        return balanceOf(account) > 0;
    }

        /**
     * @dev Remove the given token from collectionIds.
     *
     * @param from address from
     * @param tokenId tokenId to remove
     */
    function _popId(address from, uint256 tokenId) internal {
        uint256[] storage _collectionIds = collectionIds[from];
        for (uint256 i = 0; i < _collectionIds.length; i++) {
            if (_collectionIds[i] == tokenId) {
                if (i != _collectionIds.length - 1) {
                    _collectionIds[i] = _collectionIds[_collectionIds.length - 1];
                }
                _collectionIds.pop();
                break;
            }
        }
    }

    /**
     * @dev Mint a new NFT in the Collection.
     * Requirements:
     *
     * - `account` must not be zero address, check ERC721 {_mint}
     * @param account address of recipient.
     */
    function _mint(address account, uint256 tokenId) internal virtual override {
        require(tokenId <= _cap, "StandardCappedNFTCollection#_mint: CANNOT_EXCEED_MINTING_CAP");
        super._mint(account, tokenId);
        collectionIds[account].push(tokenId);
        emit NFTCreated(tokenId, account);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * @param from address from
     * @param to address to
     * @param tokenId tokenId to transfer
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(to != address(0), "CommunityNFT#_transfer: TRANSFER_TO_THE_ZERO_ADDRESS");
        super._transfer(from, to, tokenId);
        _popId(from, tokenId);
        collectionIds[to].push(tokenId);
    }
}