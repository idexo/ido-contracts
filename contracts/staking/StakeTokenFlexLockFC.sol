// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../lib/FactoryOperatorable.sol";

contract StakeTokenFlexLockFC is ERC721URIStorage, FactoryOperatorable {
    using SafeMath for uint256;
    // Last stake token id, start from 1
    uint256 public tokenIds;
    uint256 public currentSupply;

    // Base NFT URI
    string public baseURI;

    struct Stake {
        uint256 amount;
        string stakeType;
        uint256 depositedAt;
        uint256 lockedUntil;
        bool isCompounding;
    }

    struct StakeType {
        string name;
        uint256 inDays;
    }

    StakeType[] private _stakeTypes;

    // typeName => stake type index
    mapping(bytes32 => uint256) private _stakeTypesIndex;

    // stake id => stake info
    mapping(uint256 => Stake) public stakes;
    // staker wallet => stake id array
    mapping(address => uint256[]) public stakerIds;

    event StakeAmountDecreased(uint256 stakeId, uint256 decreaseAmount);
    event StakeAmountIncreased(uint256 stakeId, uint256 increaseAmount);
    event StakesAmountIncreased(uint256[] stakeIds, uint256[] increaseAmounts);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address admin,
        address operator
    ) ERC721(name_, symbol_) FactoryOperatorable(admin, operator) {
        baseURI = baseURI_;
    }

    /**
     * @dev Override supportInterface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**********************|
    |          URI         |
    |_____________________*/

    /**
     * @dev Return token URI
     * Override {ERC721URIStorage:tokenURI}
     */
    function tokenURI(uint256 tokenId) public view override(ERC721URIStorage) returns (string memory) {
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

    /**********************|
    |      StakeTypes      |
    |_____________________*/

    /**
     * @dev Add a new stakeTypes
     * @param typeName string
     * @param lockedInDays uint256
     *
     */
    function addStakeTypes(string[] calldata typeName, uint256[] calldata lockedInDays) public onlyOwner {
        require(typeName.length == lockedInDays.length, "STAKETYPE_LENGTH_MISMATCH");
        // index 0 must be an empty stakeType
        if (_stakeTypes.length == 0) _stakeTypes.push(StakeType("", 0));
        for (uint256 i = 0; i < typeName.length; i++) {
            require(bytes(typeName[i]).length != 0, "INVALID_TYPE_NAME");
            require(lockedInDays[i] > 0, "MUST_BE_BIGGER_THAN_ZERO");

            _stakeTypes.push(StakeType(typeName[i], lockedInDays[i]));
            _stakeTypesIndex[_getHash(typeName[i])] = _stakeTypes.length - 1;
        }
    }

    /**
     * @dev Returns an array with valid stakeTypes
     *
     */
    function getStakeTypes() public view returns (StakeType[] memory) {
        return _stakeTypes;
    }

    /**
     * @dev Returns information for a specific stakeType
     * @param typeName string
     */
    function getStakeTypeInfo(string memory typeName) public view returns (StakeType memory) {
        require(bytes(typeName).length != 0, "INVALID_TYPE_NAME");
        return _stakeTypes[_stakeTypesIndex[_getHash(typeName)]];
    }

    /**********************|
    |       Stake Info     |
    |_____________________*/

    /**
     * @dev Get stake token id array owned by wallet address.
     * @param account address
     */
    function getStakeTokenIds(address account) public view returns (uint256[] memory) {
        return stakerIds[account];
    }

    /**
     * @dev Return total stake amount of `account`
     * @param account address
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
     * @dev Check if wallet address owns any stake tokens.
     * @param account address
     */
    function isHolder(address account) public view returns (bool) {
        return balanceOf(account) > 0;
    }

    /**
     * @dev Return stake info from `stakeId`.
     * Requirements:
     *
     * - `stakeId` must exist in stake pool
     * @param stakeId uint256
     */
    function getStakeInfo(uint256 stakeId) public view returns (Stake memory) {
        require(_exists(stakeId), "StakeToken: STAKE_NOT_FOUND");
        return (stakes[stakeId]);
    }

    /**
     * @dev Return total stake amount that have been in the pool from `fromDate`
     * Requirements:
     *
     * - `fromDate` must be past date
     * @param fromDate uint256
     */
    function getEligibleStakeAmount(uint256 fromDate) public view returns (uint256) {
        require(fromDate <= block.timestamp, "StakeToken: NO_PAST_DATE");
        uint256 totalSAmount;

        for (uint256 i = 1; i <= tokenIds; i++) {
            if (_exists(i)) {
                Stake memory stake = stakes[i];
                if (stake.depositedAt > fromDate) {
                    break;
                }
                totalSAmount += stake.amount;
            }
        }

        return totalSAmount;
    }

    /**********************|
    |      Compound        |
    |_____________________*/

    /**
     * @dev Returns true or false if the stake is compounding
     * Requirements:
     *
     * @param stakeId uint256
     */
    function isCompounding(uint256 stakeId) external view returns (bool) {
        require(_exists(stakeId), "StakeToken: STAKE_NOT_FOUND");
        return stakes[stakeId].isCompounding;
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
     * @dev Returns the has for the passed string
     * Requirements:
     * keccak256() only accept bytes as arguments, so we need explicit conversion
     *
     * @param typeName string
     */
    function _getHash(string memory typeName) internal pure returns (bytes32) {
        return keccak256(bytes(typeName));
    }

    /**
     * @dev Returns true or false if the stake type is valid
     * Requirements:
     *
     * @param typeName string
     */
    function _validStakeType(string memory typeName) internal view returns (bool _validType) {
        uint256 typeId = _stakeTypesIndex[_getHash(typeName)];
        if (_stakeTypes[typeId].inDays != 0) return true;
        return false;
    }

    /**
     * @dev Returns the number of blocking days for the informed stake type
     * Requirements:
     *
     * @param typeName string
     */
    function _getLockDays(string memory typeName) internal view returns (uint256) {
        uint256 typeId = _stakeTypesIndex[_getHash(typeName)];
        return _stakeTypes[typeId].inDays;
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
        string memory stakeType,
        uint256 depositedAt,
        uint256 lockedUntil,
        bool autoComponding
    ) internal virtual returns (uint256) {
        require(amount > 0, "StakeToken: INVALID_AMOUNT");

        tokenIds += 1;
        currentSupply += 1;
        super._mint(account, tokenIds);
        Stake storage newStake = stakes[tokenIds];
        newStake.amount = amount;
        newStake.stakeType = stakeType;
        newStake.depositedAt = depositedAt;
        newStake.lockedUntil = lockedUntil;
        newStake.isCompounding = autoComponding;

        stakerIds[account].push(tokenIds);
        return tokenIds;
    }

    function _setCompounding(uint256 stakeId, bool compounding) internal virtual {
        if (stakes[stakeId].isCompounding != compounding) {
            stakes[stakeId].isCompounding = compounding;
        }
    }

    /**
     * @dev Burn stakeToken.
     * Requirements:
     *
     * - `stakeId` must exist in stake pool
     * @param stakeId id of buring token.
     */
    function _burn(uint256 stakeId) internal override(ERC721URIStorage) {
        require(_exists(stakeId), "StakeToken: STAKE_NOT_FOUND");
        address stakeOwner = ownerOf(stakeId);
        super._burn(stakeId);
        delete stakes[stakeId];
        currentSupply -= 1;
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
        require(_exists(stakeId), "StakeToken: STAKE_NOT_FOUND");
        require(amount <= stakes[stakeId].amount, "StakeToken: INSUFFICIENT_STAKE_AMOUNT");
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
