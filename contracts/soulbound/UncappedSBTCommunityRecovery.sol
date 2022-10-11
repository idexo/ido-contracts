// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../lib/Operatorable.sol";

contract UncappedSBTCommunityRecovery is ERC721URIStorage, Operatorable, ReentrancyGuard {
    using SafeMath for uint256;

    //Last stake token id, start from 1
    uint256 public tokenIds;

    //NFT Base URI
    string public baseURI;

    //NFT Collection Description
    string public collectionDescription;

    struct TokenInfo {
        address[] tokenOperators; //starts with token owner address
        uint256 numTokenOperators; //starts at 1 on minting i.e. tokenOwner
        uint256 requestedTransfer; //starts at 0 on minting
        bool operatorLocked; //starts at false
    }

    struct TransferInfo {
        uint256 transferId;
        address from;
        address to;
        uint256 numApprovals;
        uint256 numDisaprovals;
        address[] voters;
        uint8 approvalState; // 0 = proposed, 1 = approved, 2 = disapproved
        uint8 transferState; // 0 = pending, 1 = done, 2 = rejected
    }

    //Collection wallet => nft id
    mapping(address => uint256[]) public collectionIds;

    //Token id to its info
    mapping(uint256 => TokenInfo) public tokenInfos;

    //Token Id => pending approval
    mapping(uint256 => bool) public pendingToApproval;

    //Token id => pending transfer
    mapping(uint256 => bool) public pendingToTransfer;

    //TokenId => transferInfo[]
    mapping(uint256 => TransferInfo[]) public transferHistory;

    event NFTCreated(uint256 indexed tokenId, address indexed account);
    event RequestedTransfer(uint256 indexed tokenId, uint256 indexed transferId, address from, address to);
    event ApprovedTransfer(uint256 indexed tokenId, uint256 indexed transferId, address from, address to);
    event DisapprovedTransfer(uint256 indexed tokenId, uint256 indexed transferId, address from, address to);

    constructor(
        string memory collectionName,
        string memory collectionSymbol,
        string memory collectionBaseURI
    ) ERC721(collectionName, collectionSymbol) {
        baseURI = collectionBaseURI;
    }

    /**
     * @dev Override supportInterface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**********************|
    |     COLLECTION       |
    |_____________________*/

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
    |     DESCRIPTION      |
    |_____________________*/

    /**
     * @dev Add a description to the collection.
     * @param description string
     */
    function addDescription(string memory description) public onlyOperator {
        collectionDescription = description;
    }

    /**********************|
    |          MINT        |
    |_____________________*/

    /**
     * @dev Mint a new token.
     * @param recipient address
     * @param _tokenURI string
     */
    function mintNFT(address recipient, string memory _tokenURI) public onlyOperator returns (uint256) {
        tokenIds++;
        _mint(recipient, tokenIds);
        super._setTokenURI(tokenIds, _tokenURI);
        return tokenIds;
    }

    /**********************|
    |         UTILS        |
    |_____________________*/

    /**
     * @dev Check if wallet address owns any nfts in the collection.
     * @param account address
     */
    function isHolder(address account) public view returns (bool) {
        return balanceOf(account) > 0;
    }

    /**
     * @dev Check if wallet address is operator on a token id.
     * @param account address
     */
    function isOperator(address account, uint256 tokenId) public view returns (bool) {
        // return tokenInfos[tokenId].tokenOperators.contains(account);
        bool isOp;
        for (uint256 i = 0; i < tokenInfos[tokenId].tokenOperators.length; i++) {
            if (account == tokenInfos[tokenId].tokenOperators[i]) {
                isOp = true;
                break;
            }
        }
        return isOp;
    }

    /**
     * @dev Check if operator already approved in current transfer proposal.
     * @param account address
     */
    function approved(address account, uint256 tokenId) public view returns (bool) {
        bool v;
        TransferInfo memory current = transferHistory[tokenId][transferHistory[tokenId].length - 1];
        for (uint256 i = 0; i < current.voters.length; i++) {
            if (account == current.voters[i]) {
                v = true;
                break;
            }
        }
        return v;
    }

    /**********************|
    |       OPERATORS      |
    |_____________________*/

    /**
     * @dev Add operators.
     *
     * @param tokenId uint.
     */
    function addOperatorAsOwner(uint256 tokenId, address newOperator) public {
        require(!tokenInfos[tokenId].operatorLocked, "LOCKED_FOR_ADD_NEW_OPERATORS");
        require(msg.sender == ownerOf(tokenId), "ONLY_OWNER_CAN_ADD_INITIAL_OPERATORS");
        TokenInfo storage newTokenInfo = tokenInfos[tokenId];
        newTokenInfo.tokenOperators.push(newOperator);
        newTokenInfo.numTokenOperators++;
    }

    /**
     * @dev Lock add operators.
     *
     * @param tokenId uint.
     */
    function lockOperatorsAsOwner(uint256 tokenId) public {
        require(msg.sender == ownerOf(tokenId), "ONLY_OWNER_CAN_LOCK_OPERATORS");
        require(tokenInfos[tokenId].numTokenOperators > 2, "MIN_3_OPERATORS_TO_LOCK");
        TokenInfo storage _newTokenInfo = tokenInfos[tokenId];
        _newTokenInfo.operatorLocked = true;
    }

    /**********************|
    |       TRANSFER       |
    |_____________________*/

    /**
     * @dev Propose a transfer.
     *
     * @param from address.
     * @param to address.
     * @param _tokenId uint.
     */
    function initiateTransfer(
        address from,
        address to,
        uint256 _tokenId
    ) public {
        require(isOperator(msg.sender, _tokenId), "ONLY_OPERATORS_CAN_INITIATE_TRANSFERS");
        require(_exists(_tokenId), "INVALID_TOKEN");
        require(to != address(0), "ZERO_ADDRESS");
        require(!pendingToApproval[_tokenId], "PENDING_TRANSFER");

        transferHistory[_tokenId].push();
        uint256 nTransferId = transferHistory[_tokenId].length;
        TransferInfo storage current = (transferHistory[_tokenId][nTransferId - 1]);
        current.transferId = nTransferId;
        current.from = from;
        current.to = to;
        current.numApprovals++;
        current.voters.push(msg.sender);

        tokenInfos[_tokenId].requestedTransfer++;

        pendingToApproval[_tokenId] = true;

        emit RequestedTransfer(_tokenId, nTransferId, from, to);
    }

    /**
     * @dev Approve a transfer.
     *
     * @param _tokenId uint256.
     */
    function approveTransfer(uint256 _tokenId) public {
        require(pendingToApproval[_tokenId], "NO_PENDING_TRANSFER");
        require(isOperator(msg.sender, _tokenId), "ONLY_OPERATORS_CAN_APPROVE_TRANSFERS");

        require(!approved(msg.sender, _tokenId), "ALREADY_APPROVED_CURRENT_TRANSFER");

        TransferInfo storage current = transferHistory[_tokenId][transferHistory[_tokenId].length - 1];

        current.numApprovals++;

        if (current.numApprovals > tokenInfos[_tokenId].numTokenOperators / 2) {
            current.approvalState = 1;
            pendingToApproval[_tokenId] = false;
            pendingToTransfer[_tokenId] = true;
        }

        emit ApprovedTransfer(_tokenId, current.transferId, current.from, current.to);
    }

    /**
     * @dev Disapprove a transfer.
     *
     * @param _tokenId uint256.
     */
    function disapproveTransfer(uint256 _tokenId) public {
        require(pendingToApproval[_tokenId], "NO_PENDING_TRANSFER");
        require(isOperator(msg.sender, _tokenId), "ONLY_OPERATORS_CAN_DISAPPROVE_TRANSFERS");

        require(!approved(msg.sender, _tokenId), "ALREADY_DISAPPROVED_CURRENT_TRANSFER");

        TransferInfo storage current = transferHistory[_tokenId][transferHistory[_tokenId].length - 1];

        current.numDisaprovals++;

        if (current.numDisaprovals > tokenInfos[_tokenId].numTokenOperators / 2) {
            current.approvalState = 2;
            current.transferState = 2;
            pendingToApproval[_tokenId] = false;
            pendingToTransfer[_tokenId] = false;
        }

        emit DisapprovedTransfer(_tokenId, current.transferId, current.from, current.to);
    }

    /**
     * @dev Finalize transfer if approved.
     *
     * @param tokenId uint256.
     */
    function finalizeTransfer(uint256 tokenId) public onlyOperator {
        require(pendingToTransfer[tokenId], "NO_PENDING_TRANSFER");
        TransferInfo storage current = transferHistory[tokenId][transferHistory[tokenId].length - 1];
        _safeTransfer(current.from, current.to, tokenId, "");
        current.transferState = 1;
    }

    /**
     * @dev Get transfer history.
     *
     * @param tokenId uint256.
     */
    function getHistory(uint256 tokenId) public view returns (TransferInfo[] memory history) {
        return transferHistory[tokenId];
    }

    /**********************|
    |      INTERNALS       |
    |_____________________*/

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
        emit NFTCreated(tokenId, account);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal override {
        super._safeTransfer(from, to, tokenId, data);
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
        if (from != address(0)) {
            require(pendingToTransfer[tokenId], "TRANSFER_LOCKED_ON_SBT_UNLESS_AUTHORIZED");
            require(transferHistory[tokenId][transferHistory[tokenId].length - 1].to == to, "RECIPIENT_NOT_AUTHORIZED");
        }
        super._transfer(from, to, tokenId);
        _popId(from, tokenId);
        collectionIds[to].push(tokenId);
        pendingToTransfer[tokenId] = false;
    }
}
