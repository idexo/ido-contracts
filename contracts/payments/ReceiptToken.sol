// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IReceiptToken.sol";
import "../lib/Operatorable.sol";
import "../lib/StakeMath.sol";

contract ReceiptToken is IReceiptToken, ERC721, ERC721URIStorage, Operatorable {
    using SafeMath for uint256;
    using StakeMath for uint256;
    // Last stake token id, start from 1
    uint256 private receiptIds;
    // current supply
    uint256 private _currentSupply;

    // Base NFT URI
    string public baseURI;

    // receipt id => receipt info
    mapping(uint256 => Receipt) public override receipts;
    // receipt wallet => receipt id array
    mapping(address => uint256[]) public override payerIds;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_
    ) ERC721(name_, symbol_) {
        baseURI = baseURI_;
    }

    /**
     * @dev Override supportInterface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**********************|
    |          URI         |
    |_____________________*/

    /**
     * @dev Return token URI
     * Override {ERC721URIStorage:tokenURI}
     */
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return ERC721URIStorage.tokenURI(tokenId);
    }

    /**
     * @dev Set token URI
     * Only `operator` can call
     * - `tokenId` must exist, see {ERC721URIStorage:_setTokenURI}
     */
    function setTokenURI(uint256 tokenId, string memory _tokenURI) public onlyOwner {
        super._setTokenURI(tokenId, _tokenURI);
    }

    /**
     * @dev Set `baseURI`
     * Only `operator` can call
     */
    function setBaseURI(string memory baseURI_) public onlyOwner {
        baseURI = baseURI_;
    }

    /*************************|
    |         Receipts        |
    |________________________*/

    /**
     * @dev Return receipt id array owned by wallet address.
     *
     * @param account address
     */
    function getReceiptIds(address account) public view override returns (uint256[] memory) {
        require(account != address(0), "ReceiptToken#getReceiptIds: ZERO_ADDRESS");
        return payerIds[account];
    }

    /**
     * @dev Return receipt info from `receiptId`.
     *
     * Requirements:
     * - `receiptId` must exist in receipt pool
     * @param receiptId uint256
     */
    function getReceiptInfo(uint256 receiptId) public view override returns (Receipt memory) {
        require(_exists(receiptId), "ReceiptToken#getReceiptInfo: RECEIPT_NOT_FOUND");
        return Receipt(receipts[receiptId].productId, receipts[receiptId].paidAmount, receipts[receiptId].paidAt);
    }

    /*************************|
    |     Current Supply      |
    |________________________*/

    /**
     * @dev Return current receipt supply.
     */
    function currentSupply() public view returns (uint256) {
        return _currentSupply;
    }

    /*************************|
    |   Private Functions     |
    |________________________*/

    /**
     * @dev Return base URI
     * Override {ERC721:_baseURI}
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Remove the given receipt from receiptIds.
     *
     * @param from address from
     * @param receiptId receiptId to remove
     */
    function _popStake(address from, uint256 receiptId) internal {
        uint256[] storage tokenIds = payerIds[from];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (tokenIds[i] == receiptId) {
                if (i != tokenIds.length - 1) {
                    tokenIds[i] = tokenIds[tokenIds.length - 1];
                }
                tokenIds.pop();
                break;
            }
        }
    }

    /**
     * @dev Mint a new ReceiptToken.
     * Requirements:
     *
     * - `account` must not be zero address, check ERC721 {_mint}
     * - `amount` must not be zero
     * @param account address of recipient.
     * @param productId id of product.
     * @param amount payment amount.
     * @param paidAt timestamp when payment amount was paid.
     */
    function _mint(
        address account,
        string memory productId,
        uint256 amount,
        uint256 paidAt
    ) internal virtual returns (uint256) {
        require(amount > 0, "ReceiptToken#_mint: INVALID_AMOUNT");
        receiptIds++;
        _currentSupply++;
        super._mint(account, receiptIds);
        Receipt storage newReceipt = receipts[receiptIds];
        newReceipt.productId = productId;
        newReceipt.paidAmount = amount;
        newReceipt.paidAt = paidAt;
        payerIds[account].push(receiptIds);

        return receiptIds;
    }

    /**
     * @dev Burn receipt - maybe in case of refund?
     * Requirements:
     *
     * - `receiptId` must exist in stake pool
     * @param receiptId id of buring token.
     */
    function _burn(uint256 receiptId) internal override(ERC721, ERC721URIStorage) {
        require(_exists(receiptId), "ReceiptToken#_burn: RECEIPT_NOT_FOUND");
        address receiptOwner = ownerOf(receiptId);
        super._burn(receiptId);
        delete receipts[receiptId];
        _popStake(receiptOwner, receiptId);
        _currentSupply--;
    }

    /**
     * @dev Transfers `receiptId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - transfers not allowed
     * @param from address from
     * @param to address to
     * @param receiptId tokenId to transfer
     */
    function _transfer(
        address from,
        address to,
        uint256 receiptId
    ) internal pure override {
        require(receiptId != 0, "ReceiptToken: INVALID_TOKEN");
        require(from == address(0) || to == address(0), "ReceiptToken: NON_TRANSFERRABLE");
    }
}
