// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IStakeMirrorNFT.sol";

/**
 * Informational mirror NFT that represents Stake NFT on Ethereum.
 * Deployed on sidechain.
 */

contract StakeMirrorNFT is IStakeMirrorNFT, ERC721, ERC721URIStorage, Ownable, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant multiplierDenominator = 100;
    // Base NFT URI
    string public baseURI;

    struct Stake {
        uint256 amount;
        uint256 multiplier;
        uint256 depositedAt;
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

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @dev Override supportInterface.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public view virtual override(IERC165, ERC721, AccessControl) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /***********************|
    |          Role         |
    |______________________*/

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "StakeMirrorNFT: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     */
    function addOperator(address account) public override onlyOwner {
        // Check if `account` already has operator role
        require(!hasRole(OPERATOR_ROLE, account), "StakeMirrorNFT: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     */
    function removeOperator(address account) public override onlyOwner {
        // Check if `account` has operator role
        require(hasRole(OPERATOR_ROLE, account), "StakeMirrorNFT: NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     */
    function checkOperator(address account) public override view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
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
    function setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) public onlyOperator {
        super._setTokenURI(tokenId, _tokenURI);
    }

    /**
     * @dev Set `baseURI`
     * Only `operator` can call
     */
    function setBaseURI(string memory baseURI_) public onlyOperator {
        baseURI = baseURI_;
    }

    /**
     * @dev Return base URI
     * Override {ERC721:_baseURI}
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /************************|
    |          Stake         |
    |_______________________*/

    /**
     * @dev Get stake token id array owned by `account`.
     */
    function getStakerIds(address account) public override view returns (uint256[] memory) {
        return stakerIds[account];
    }

    /**
     * @dev Return total stake amount of `account`
     */
    function getStakeAmount(address account) external view returns (uint256 totalStakeAmount) {
        uint256[] memory stakeIds = stakerIds[account];
        for (uint256 i = 0; i < stakeIds.length; i++) {
            totalStakeAmount += stakes[stakeIds[i]].amount;
        }
    }

    /**
     * @dev Check if `account` owns any stake tokens.
     */
    function isHolder(address account) public override view returns (bool) {
        return balanceOf(account) > 0;
    }

    /**
     * @dev Mint a new StakeMirrorNFT.
     * Only `operator` can call
     *
     * - `account` must not be zero address, check ERC721 {_mint}
     * - `tokenId` must not be zero
     * - `amount` must not be zero
     */
    function mint(
        address account,
        uint256 tokenId,
        uint256 amount,
        uint256 multiplier,
        uint256 depositedAt
    ) public onlyOperator returns (uint256) {
        require(tokenId > 0, "StakeMirrorNFT: INVALID_TOKEN_ID");
        require(amount > 0, "StakeMirrorNFT: INVALID_AMOUNT");
        super._mint(account, tokenId);
        Stake storage newStake = stakes[tokenId];
        newStake.amount = amount;
        newStake.multiplier = multiplier;
        newStake.depositedAt = depositedAt;
        stakerIds[account].push(tokenId);

        return tokenId;
    }

    /**
     * @dev Burn StakeMirrorNFT.
     *
     * - `stakeId` must exist
     */
    function _burn(uint256 stakeId) internal override(ERC721, ERC721URIStorage) {
        require(_exists(stakeId), "StakeMirrorNFT: STAKE_NOT_FOUND");
        address stakeOwner = ownerOf(stakeId);
        ERC721URIStorage._burn(stakeId);
        delete stakes[stakeId];
        uint256[] storage stakeIds = stakerIds[stakeOwner];
        for (uint256 i = 0; i < stakeIds.length; i++) {
            if (stakeIds[i] == stakeId) {
                if (i != stakeIds.length - 1) {
                    stakeIds[i] = stakeIds[stakeIds.length - 1];
                }
                stakeIds.pop();
                break;
            }
        }
    }

    /**
     * @dev Decrease stake amount by `amount`.
     * If stake amount leads to be zero, the stake is burned.
     * Only `operator` can call
     *
     * - `stakeId` must exist
     */
    function decreaseStakeAmount(
        uint256 stakeId,
        uint256 amount
    ) public onlyOperator {
        require(_exists(stakeId), "StakeMirrorNFT: STAKE_NOT_FOUND");
        require(amount <= stakes[stakeId].amount, "StakeMirrorNFT: INSUFFICIENT_STAKE_AMOUNT");
        if (amount == stakes[stakeId].amount) {
            _burn(stakeId);
        } else {
            stakes[stakeId].amount -= amount;
            emit StakeAmountDecreased(stakeId, amount);
        }
    }

    /**
     * @dev Limit NFT transfer to `operator`
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(hasRole(OPERATOR_ROLE, msg.sender), "StakeMirrorNFT: CALLER_NO_OPERATOR_ROLE");
    }
}
