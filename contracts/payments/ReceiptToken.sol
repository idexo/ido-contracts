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

    uint256 public constant multiplierDenominator = 100;

    // Base NFT URI
    string public baseURI;

    struct Receipt {
        uint256 amount;
        uint256 paidAt;
        uint256 productId;
    }
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
     *
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

    /**
     * @dev Get receipt id array owned by wallet address.
     * @param account address
     */
    function getReceiptIds(address account) public view override returns (uint256[] memory) {
        return payerIds[account];
    }

    /**
     * @dev Return total paid amount of `account`
     */
    function getPaidAmount(address account) external view returns (uint256) {
        uint256[] memory receiptIds = receiptIds[account];
        uint256 totalPaidAmount;
        for (uint256 i = 0; i < receiptIds.length; i++) {
            totalPaidAmount += receipts[receiptIds[i]].amount;
        }
        return totalPaidAmount;
    }

    /**
     * @dev Check if wallet address owns any receipt tokens.
     * @param account address
     */
    function hasPaid(address account) public view override returns (bool) {
        //this one gets tricky if we wanted to specify a product
        //it may be easier to have one contract per one product
        //then we can simply use below logic without using product id
        //or we can use hasPaid, then follow it up with getReceipts and parse the results
        //to check for a matching productId
        return balanceOf(account) > 0;
    }

    /**
     * @dev Return recceipt info from `receiptId`.
     * Requirements:
     *
     * - `receiptId` must exist in receipt pool
     * @param stakeId uint256
     */
    function getReceiptInfo(uint256 receiptId)
        public
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(_exists(receiptId), "ReceiptToken#getReceiptInfo: RECEIPT_NOT_FOUND");
        return (receipts[receiptId].amount, receipts[receiptId].paiddAt, receipts[receiptId].productId);
    }

    

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
        uint256[] storage receiptIds = payerIds[from];
        for (uint256 i = 0; i < receiptIds.length; i++) {
            if (receiptIds[i] == receiptId) {
                if (i != receiptIds.length - 1) {
                    receiptIds[i] = receiptIds[receiptIds.length - 1];
                }
                receiptIds.pop();
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
     * @param amount payment amount.
     * @param paiddAt timestamp when payment amount was paid.
     */
    function _mint(
        address account,
        uint256 amount,
        uint256 depositedAt,
        uint256 timestamplock
    ) internal virtual returns (uint256) {
        require(amount > 0, "StakeToken#_mint: INVALID_AMOUNT");
        tokenIds++;
        _currentSupply++;
        super._mint(account, tokenIds);
        Stake storage newStake = stakes[tokenIds];
        newStake.amount = amount;
        newStake.multiplier = tokenIds.multiplier();
        newStake.depositedAt = depositedAt;
        newStake.timestamplock = timestamplock;
        stakerIds[account].push(tokenIds);

        return tokenIds;
    }

    /**
     * @dev Burn receipt - maybe in case of refund?
     * Requirements:
     *
     * - `stakeId` must exist in stake pool
     * @param stakeId id of buring token.
     */
    function _burn(uint256 stakeId) internal override(ERC721, ERC721URIStorage) {
        require(_exists(stakeId), "StakeToken#_burn: STAKE_NOT_FOUND");
        address stakeOwner = ownerOf(stakeId);
        super._burn(stakeId);
        delete stakes[stakeId];
        _currentSupply--;
        
    }

   

    /**
     * @dev Transfers `receiptId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `receiptId` token must be owned by `from`.
     *
     * @param from address from
     * @param to address to
     * @param tokenId tokenId to transfer
     */
    function _transfer(
        address from,
        address to,
        uint256 receiptId
    ) internal override {
        super._transfer(from, to, receiptId);
        _popStake(from, receiptId);
        receiptIds[to].push(receiptId);
    }
}
