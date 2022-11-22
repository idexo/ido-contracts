// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IStakeTokenNew.sol";
import "../lib/StakeMath.sol";

contract StakeTokenNew is IStakeTokenNew, ERC721, ERC721URIStorage, Ownable2Step {
    using SafeMath for uint256;
    using StakeMath for uint256;
    // Last stake token id, start from 1
    uint256 public tokenIds;
    uint256 public constant multiplierDenominator = 100;

    // Base NFT URI
    string public baseURI;

    struct Stake {
        uint256 amount;
        uint256 multiplier;
        uint256 depositedAt;
        uint256 timestamplock;
    }
    // stake id => stake info
    mapping(uint256 => Stake) public override stakes;
    // staker wallet => stake id array
    mapping(address => uint256[]) public override stakerIds;

    event StakeAmountDecreased(uint256 stakeId, uint256 decreaseAmount);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_
    ) ERC721(name_, symbol_) {
        baseURI = baseURI_;
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
     * @dev Return base URI
     * Override {ERC721:_baseURI}
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Get stake token id array owned by wallet address.
     * @param account address
     */
    function getStakeTokenIds(address account) public view override returns (uint256[] memory) {
        return stakerIds[account];
    }

    /**
     * @dev Return total stake amount of `account`
     */
    function getStakeAmount(address account) external view returns (uint256) {
        uint256[] memory stakeIds = stakerIds[account];
        uint256 totalStakeAmount;
        for (uint256 i = 0; i < stakeIds.length; i++) {
            totalStakeAmount += stakes[stakeIds[i]].amount;
        }
        return totalStakeAmount;
    }

    /**
     * @dev Remove the given token from stakerIds.
     *
     * @param from address from
     * @param tokenId tokenId to remove
     */
    function _popStake(address from, uint256 tokenId) internal {
        uint256[] storage stakeIds = stakerIds[from];
        for (uint256 i = 0; i < stakeIds.length; i++) {
            if (stakeIds[i] == tokenId) {
                if (i != stakeIds.length - 1) {
                    stakeIds[i] = stakeIds[stakeIds.length - 1];
                }
                stakeIds.pop();
                break;
            }
        }
    }

    /**
     * @dev Check if wallet address owns any stake tokens.
     * @param account address
     */
    function isHolder(address account) public view override returns (bool) {
        return balanceOf(account) > 0;
    }

    /**
     * @dev Return stake info from `stakeId`.
     * Requirements:
     *
     * - `stakeId` must exist in stake pool
     * @param stakeId uint256
     */
    function getStakeInfo(uint256 stakeId)
        public
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        require(_exists(stakeId), "StakeToken#getStakeInfo: STAKE_NOT_FOUND");
        return (stakes[stakeId].amount, stakes[stakeId].multiplier, stakes[stakeId].depositedAt, stakes[stakeId].timestamplock);
    }

    /**
     * @dev Return total stake amount that have been in the pool from `fromDate`
     * Requirements:
     *
     * - `fromDate` must be past date
     */
    function getEligibleStakeAmount(uint256 fromDate) public view override returns (uint256) {
        require(fromDate <= block.timestamp, "StakeToken#getEligibleStakeAmount: NO_PAST_DATE");
        uint256 totalSAmount;

        for (uint256 i = 1; i <= tokenIds; i++) {
            if (_exists(i)) {
                Stake memory stake = stakes[i];
                if (stake.depositedAt > fromDate) {
                    break;
                }
                totalSAmount += (stake.amount * stake.multiplier) / multiplierDenominator;
            }
        }

        return totalSAmount;
    }

    /**
     * @dev Mint a new StakeToken.
     * Requirements:
     *
     * - `account` must not be zero address, check ERC721 {_mint}
     * - `amount` must not be zero
     * @param account address of recipient.
     * @param amount mint amount.
     * @param depositedAt timestamp when stake was deposited.
     */
    function _mint(
        address account,
        uint256 amount,
        uint256 depositedAt,
        uint256 timestamplock
    ) internal virtual returns (uint256) {
        require(amount > 0, "StakeToken#_mint: INVALID_AMOUNT");
        tokenIds++;
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
     * @dev Burn stakeToken.
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
        _popStake(stakeOwner, stakeId);
    }

    /**
     * @dev Decrease stake amount.
     * If stake amount leads to be zero, the stake is burned.
     * Requirements:
     *
     * - `stakeId` must exist in stake pool
     * @param stakeId id of buring token.
     * @param amount to withdraw.
     */
    function _decreaseStakeAmount(uint256 stakeId, uint256 amount) internal virtual {
        require(_exists(stakeId), "StakeToken#_decreaseStakeAmount: STAKE_NOT_FOUND");
        require(amount <= stakes[stakeId].amount, "StakeToken#_decreaseStakeAmount: INSUFFICIENT_STAKE_AMOUNT");
        if (amount == stakes[stakeId].amount) {
            _burn(stakeId);
        } else {
            stakes[stakeId].amount = stakes[stakeId].amount.sub(amount);
            emit StakeAmountDecreased(stakeId, amount);
        }
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
        super._transfer(from, to, tokenId);
        _popStake(from, tokenId);
        stakerIds[to].push(tokenId);
    }
}
