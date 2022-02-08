// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract CommunityNFT is
    ERC721URIStorage,
    AccessControl,
    ReentrancyGuard
{
    using SafeMath for uint256;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

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

    constructor(
        string memory communityNFTname,
        string memory communityNFTsymbol,
        string memory communityNFTBaseURI
    ) ERC721(communityNFTname, communityNFTsymbol) {
        baseURI = communityNFTBaseURI;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @dev Override supportInterface.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC721)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /***********************|
    |          Role         |
    |______________________*/

    /**
     * @dev Restricted to members of the admin role.
     */
    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "CommunityNFT#onlyAdmin: CALLER_NO_ADMIN_ROLE"
        );
        _;
    }

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, msg.sender),
            "CommunityNFT#onlyOperator: CALLER_NO_OPERATOR_ROLE"
        );
        _;
    }

    /**
     * @dev Add an account to the operator role.
     * @param account address of recipient.
     */
    function addOperator(address account) public onlyAdmin {
        // Check if `account` already has operator role
        require(
            !hasRole(OPERATOR_ROLE, account),
            "CommunityNFT#addOperator: ALREADY_OPERATOR_ROLE"
        );
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     * @param account address.
     */
    function removeOperator(address account) public onlyAdmin {
        // Check if `account` has operator role
        require(
            hasRole(OPERATOR_ROLE, account),
            "CommunityNFT#removeOperator: NO_OPERATOR_ROLE"
        );
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     * @param account address of operator being checked.
     */
    function checkOperator(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /**********************|
    |          URI         |
    |_____________________*/

    /**
     * @dev Return token URI
     * Override {ERC721URIStorage:tokenURI}
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return ERC721URIStorage.tokenURI(tokenId);
    }

    /**
     * @dev Set token URI
     * Only `operator` can call
     *
     * - `tokenId` must exist, see {ERC721URIStorage:_setTokenURI}
     */
    function setTokenURI(uint256 tokenId, string memory _tokenURI)
        public
        onlyOperator
    {
        super._setTokenURI(tokenId, _tokenURI);
    }

    /**
     * @dev Set `baseURI`
     * Only `operator` can call
     */
    function setBaseURI(string memory baseURI_) public onlyAdmin {
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
    function mintNFT(address recipient) public onlyOperator returns (uint256) {
        // Check if `account` already has a token id
        require(
            !isHolder(recipient),
            "CommunityNFT#mintNFT: ACCOUNT_ALREADY_HAS_NFT"
        );

        tokenIds++;
        _mint(recipient, tokenIds);

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
    function updateNFTRank(uint256 nftId, string memory newRank)
        public
        onlyOperator
    {
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
    function moveNFT(
        address from,
        address to,
        uint256 tokenId
    ) public onlyOperator {
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
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(
            to != address(0),
            "CommunityNFT#_transfer: TRANSFER_TO_THE_ZERO_ADDRESS"
        );
        // Check if `account` already has a token id
        require(
            !isHolder(to),
            "CommunityNFT#_transfer: ACCOUNT_ALREADY_HAS_NFT"
        );
        super._transfer(from, to, tokenId);
        delete communityIds[from];
        communityIds[to] = tokenId;
    }

    /**
     * @dev Burn token. Not reachable.
     */
    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        require(_exists(tokenId), "CommunityNFT#burnNFT: TOKEN_NOT_FOUND");
        super._burn(tokenId);
    }
}
