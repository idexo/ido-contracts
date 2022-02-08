// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../lib/Operatorable.sol";

contract CommunityNFT is ERC721URIStorage, Operatorable, ReentrancyGuard {
    using SafeMath for uint256;

    //Last stake token id, start from 1
    uint256 public tokenIds;

    //NFT Base URI
    string public baseURI;

    //Historical CRED earned all-time for a token id
    mapping(uint256 => uint256) public credEarned;

    //Community Rank assigned to a token id
    mapping(uint256 => string) public communityRank;

    //Idexonaut wallet => nft id
    mapping(address => uint256) public communityIds;

    event NFTCreated(uint256 indexed nftId, address indexed account);
    event CREDAdded(uint256 indexed nftId, uint256 credAddedAmount);
    event RankUpdated(uint256 indexed nftId, string newRank);

    constructor(string memory communityNFTname, string memory communityNFTsymbol, string memory communityNFTBaseURI ) ERC721(communityNFTname, communityNFTsymbol) {
        baseURI = communityNFTBaseURI;
    }

    /**
     * @dev Override supportInterface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
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
    |          MINT        |
    |_____________________*/

    /**
     * @dev Mint a new token.
     * @param recipient address
     * check that recipient does not already have one, if they do then mint fails
     */
    function mintNFT(address recipient, string memory _tokenURI) public onlyOperator returns (uint256) {
        // Check if `account` already has a token id
        require(!isHolder(recipient), "CommunityNFT#mintNFT: ACCOUNT_ALREADY_HAS_NFT");

        tokenIds++;
        _mint(recipient, tokenIds);
        super._setTokenURI(tokenIds, _tokenURI);
        return tokenIds;
    }

    /**
     * @dev Check if wallet address owns any stake tokens.
     * @param account address
     */
    function isHolder(address account) public view returns (bool) {
        return balanceOf(account) > 0;
    }

    /**
     * @dev Get token id array owned by wallet address.
     * @param account address
     */
    function getTokenId(address account) public view returns (uint256) {
        require(account != address(0), "ERC721: token query for account(0");
        uint256 tokenId = communityIds[account];
        return tokenId;
    }

    /**********************|
    |       UPDATES        |
    |_____________________*/

    /**
     * @dev Updated historical credEarned info for `nftId`.
     * Requirements:
     *
     * - `nftId` must exist in the community nft collection
     * @param nftId uint256
     */
    function updateNFTCredEarned(uint256 nftId, uint256 newCredEarned)
        public
        onlyOperator
    {
        credEarned[nftId] = credEarned[nftId] + newCredEarned;
        emit CREDAdded(nftId, newCredEarned);
    }

    /**
     * @dev Updated historical credEarned info for `nftId`.
     * Requirements:
     *
     * - `nftId` must exist in the community nft collection
     * @param nftId uint256
     */
    function updateNFTRank(uint256 nftId, string memory newRank) public onlyOperator {
        communityRank[nftId] = newRank;
        emit RankUpdated(nftId, newRank);
    }

    /**********************|
    |          MOVE        |
    |_____________________*/

    /**
     * @dev Transfer a token without approve.
     * @param from address from
     * @param to address to
     * @param tokenId tokenId to transfer
     */
    function moveNFT(address from, address to, uint256 tokenId ) public onlyOperator {
        _transfer(from, to, tokenId);
    }

    /**
     * @dev Mint a new StakeToken.
     * Requirements:
     *
     * - `account` must not be zero address, check ERC721 {_mint}
     * @param account address of recipient.
     */
    function _mint(address account, uint256 tokenId) internal virtual override {
        super._mint(account, tokenId);
        communityIds[account] = tokenId;
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
    function _transfer(address from, address to, uint256 tokenId ) internal override {
        require(to != address(0), "CommunityNFT#_transfer: TRANSFER_TO_THE_ZERO_ADDRESS");
        // Check if `account` already has a token id
        require(!isHolder(to), "CommunityNFT#_transfer: ACCOUNT_ALREADY_HAS_NFT");
        super._transfer(from, to, tokenId);
        delete communityIds[from];
        communityIds[to] = tokenId;
    }
}
