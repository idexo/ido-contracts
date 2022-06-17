// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IStakeTokenFlexLock.sol";
import "../lib/Operatorable.sol";
import "../lib/StakeMath.sol";

contract StakeTokenFlexLock is IStakeTokenFlexLock, ERC721URIStorage, Operatorable {
    using SafeMath for uint256;
    using StakeMath for uint256;
    // Last stake token id, start from 1
    uint256 private tokenIds;
    // current supply
    uint256 private _currentSupply;

    uint256 public constant multiplierDenominator = 100;

    // Base NFT URI
    string public baseURI;

    struct Stake {
        uint256 amount;
        uint256 multiplier;
        string stakeType;
        uint256 depositedAt;
        uint256 lockedUntil;
        bool compounding;
    }

    struct StakeType {
        string name;
        uint256 inDays;
    }

    string[] public acceptedTypes;

    uint256[] private _compoundIds;

    mapping(bytes32 => StakeType) private _stakeTypes;

    // stake id => stake info
    mapping(uint256 => Stake) public override stakes;
    // staker wallet => stake id array
    mapping(address => uint256[]) public override stakerIds;

    event StakeAmountDecreased(uint256 stakeId, uint256 decreaseAmount);
    event StakeAmountIncreased(uint256 stakeId, uint256 increaseAmount);

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
            string memory,
            uint256,
            uint256,
            bool
        )
    {
        require(_exists(stakeId), "StakeToken#getStakeInfo: STAKE_NOT_FOUND");
        return (
            stakes[stakeId].amount,
            stakes[stakeId].multiplier,
            stakes[stakeId].stakeType,
            stakes[stakeId].depositedAt,
            stakes[stakeId].lockedUntil,
            stakes[stakeId].compounding
        );
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

    function currentSupply() public view returns (uint256) {
        return _currentSupply;
    }

    /**********************|
    |      STAKETYPES      |
    |_____________________*/

    function addStakeType(string memory typeName, uint256 lockedInDays) public onlyOwner {
        // keccak256() only accept bytes as arguments, so we need explicit conversion
        bytes memory name = bytes(typeName);
        bytes32 typeHash = keccak256(name);

        StakeType storage newType = _stakeTypes[typeHash];
        newType.name = typeName;
        newType.inDays = lockedInDays;

        acceptedTypes.push(typeName);
    }

    /*************************|
    |   Private Functions     |
    |________________________*/

    function _getHash(string memory string_to) internal returns (bytes32) {
        // TODO: DRY
    }

    function _getLockDays(string memory stakeType) internal view returns (uint256) {
        // keccak256() only accept bytes as arguments, so we need explicit conversion
        bytes memory name = bytes(stakeType);
        bytes32 typeHash = keccak256(name);

        return _stakeTypes[typeHash].inDays;
    }

    /**
     * @dev Return base URI
     * Override {ERC721:_baseURI}
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Returns StakeToken multiplier.
     *
     * @param tokenId the tokenId to check
     *
     * 0 < `tokenId` <300: 120.
     * 300 <= `tokenId` <4000: 110.
     * 4000 <= `tokenId`: 100.
     */
    function getMultiplier(uint256 tokenId) public pure returns (uint256) {
        return tokenId.multiplier();
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

    function _validStakeType(string memory typeName) internal view returns (bool _validType) {
        // keccak256() only accept bytes as arguments, so we need explicit conversion
        bytes memory name = bytes(typeName);
        bytes32 typeHash = keccak256(name);
        if(_stakeTypes[typeHash].inDays != 0) return true;
        return false;
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
        require(amount > 0, "StakeToken#_mint: INVALID_AMOUNT");

        require(_validStakeType(stakeType), "STAKE_TYPE_NOT_FOUND");

        tokenIds++;
        _currentSupply++;
        super._mint(account, tokenIds);
        Stake storage newStake = stakes[tokenIds];
        newStake.amount = amount;
        newStake.multiplier = tokenIds.multiplier();
        newStake.stakeType = stakeType;
        newStake.depositedAt = depositedAt;
        newStake.lockedUntil = lockedUntil;
        newStake.compounding = autoComponding;
        stakerIds[account].push(tokenIds);

        if (autoComponding) _compoundIds.push(tokenIds);

        return tokenIds;
    }

    function _addStake(uint256 stakeId, uint256 amount) internal virtual {
        require(_exists(stakeId), "StakeToken#_burn: STAKE_NOT_FOUND");
        require(stakes[stakeId].lockedUntil < block.timestamp, "StakePool#addStake: STAKE_IS_LOCKED");
        require(amount > 0, "StakeToken#_mint: INVALID_AMOUNT");

        // TODO: add transfer amount function
        stakes[stakeId].amount = stakes[stakeId].amount.add(amount);
        emit StakeAmountIncreased(stakeId, amount);
    }

    function _setCompounding(uint256 stakeId, bool compounding) internal virtual {
        // TODO: only token owner
        stakes[stakeId].compounding = compounding;
        if (!compounding) _popCompound(stakeId);
        if (compounding) _compoundIds.push(tokenIds);
    }

    function isCompounding(uint256 stakeId) external view returns (bool) {
        // TODO: check if exists
        return stakes[stakeId].compounding;
    }

    function getCompoundingIds() external view returns (uint256[] memory) {
        return _compoundIds;
    }

    /**
     * @dev Burn stakeToken.
     * Requirements:
     *
     * - `stakeId` must exist in stake pool
     * @param stakeId id of buring token.
     */
    function _burn(uint256 stakeId) internal override(ERC721URIStorage) {
        require(_exists(stakeId), "StakeToken#_burn: STAKE_NOT_FOUND");
        address stakeOwner = ownerOf(stakeId);
        super._burn(stakeId);
        delete stakes[stakeId];
        _currentSupply--;
        _popStake(stakeOwner, stakeId);
        _popCompound(stakeId);
    }

    /**
     * @dev Remove the given token from stakerIds.
     *
     * @param tokenId tokenId to remove
     */
    function _popCompound(uint256 tokenId) internal {
        uint256[] storage compoundIds = _compoundIds;
        for (uint256 i = 0; i < compoundIds.length; i++) {
            if (compoundIds[i] == tokenId) {
                if (i != compoundIds.length - 1) {
                    compoundIds[i] = compoundIds[compoundIds.length - 1];
                }
                compoundIds.pop();
                break;
            }
        }
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
