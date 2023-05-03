// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../lib/FactoryOperatorable.sol";

contract UncappedLinkedSoulboundFC is ERC721URIStorage, FactoryOperatorable, ReentrancyGuard {
    using SafeMath for uint256;

    //Last stake token id, start from 1
    uint256 public tokenIds;

    //NFT Base URI
    string public baseURI;

    //NFT Collection Description
    string public collectionDescription;

    //LinkedNFT Struct
    struct LinkedNFT {
        uint256 chainId;
        address contractAddress;
        uint256 tokenId;
    }

    //Collection wallet => nft id
    mapping(address => uint256[]) public collectionIds;

    //tokenId => array of LinkedNFTs
    mapping(uint256 => LinkedNFT[]) public linkedNFTs;

    event SBTCreated(uint256 indexed nftId, address indexed account);
    

    constructor(
        string memory collectionName,
        string memory collectionSymbol,
        string memory collectionBaseURI,
        address admin,
        address operator
    ) ERC721(collectionName, collectionSymbol) FactoryOperatorable(admin, operator) {
        baseURI = collectionBaseURI;
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
    |          LinkedNFTs  |
    |_____________________*/

    function addLinkedNFT(uint256 tokenId, uint256 chainId, address contractAddress, uint256 _tokenId) public onlyOperator {
        LinkedNFT memory newLinkedNFT;
        newLinkedNFT.chainId = chainId;
        newLinkedNFT.contractAddress = contractAddress;
        newLinkedNFT.tokenId = _tokenId;
        linkedNFTs[tokenId].push(newLinkedNFT);


    }

    /**
     * @dev Get linked NFTs array for a given token id
     * @param _tokenId uint256
     */
    function getLinkedNFTs(uint256 _tokenId) public view returns (LinkedNFT[] memory) {
        return linkedNFTs[_tokenId];
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
    function mintSBT(address recipient, string memory _tokenURI) public onlyOperator returns (uint256) {
        

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
    function mintBatchSBT(
        address[] memory recipients,
        string[] memory tokenURIs
    )
        public
        onlyOperator
    {
        require(recipients.length == tokenURIs.length, "StandardCappedNFTCollection#mintBatchNFT: PARAMS_LENGTH_MISMATCH");
        for (uint256 i = 0; i < recipients.length; i++) {
            mintSBT(recipients[i], tokenURIs[i]);
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
     * override safeTransferFrom to error if not contract owner
     */
    function safeTransferFrom (address _from, address _to, uint256 _tokenId) public override {
        require(msg.sender == owner(), "SoulBoundNFT#_transfer: TRANSFER_LOCKED_ON_SBT");
        _transfer(_from, _to, _tokenId);
    }

     /**
     * override safeTransferFrom with data to error if not contract owner
     */
    function safeTransferFrom (address from, address to, uint256 tokenId, bytes memory _data) public override {
        require(msg.sender == owner(), "SoulBoundNFT#_transfer: TRANSFER_LOCKED_ON_SBT");
        _safeTransfer(from, to, tokenId, _data);
    }

    /**
     * override transferFrom to error if not contract owner
     */
    function transferFrom (address _from, address _to, uint256 _tokenId) public override {
        require(msg.sender == owner(), "SoulBoundNFT#_transfer: TRANSFER_LOCKED_ON_SBT");
        _transfer(_from, _to, _tokenId);
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
        super._mint(account, tokenId);
        collectionIds[account].push(tokenId);
        emit SBTCreated(tokenId, account);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
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
        super._transfer(from, to, tokenId);
        _popId(from, tokenId);
        collectionIds[to].push(tokenId);
    }
}