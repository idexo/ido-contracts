// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./BaseRoyaltyNFT.sol";

contract RoyaltyNFT is BaseRoyaltyNFT {
    // Royalties fee in Basis Points
    uint16 public royaltiesFeeBP; // This variable does not have a value of 1000, it is necessary to increase the size of the uint

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI,
        address _royaltiesCollector,
        uint16 _royaltiesFeeBP
    ) BaseRoyaltyNFT(_name, _symbol, _baseTokenURI, _royaltiesCollector) {
        require(_royaltiesFeeBP <= 1000, "INVALID_ROYALTIES_FEE");
        royaltiesFeeBP = _royaltiesFeeBP;
    }

    /**
     * @dev Set `royaltiesFeeBP`
     * Only `owner` can call
     * `_royaltiesFeeBP` must not be greater than 1000
     */
    function setRoyaltiesFeeBP(uint16 _royaltiesFeeBP) external onlyOwner {
        require(_royaltiesFeeBP <= 1000, "INVALID_ROYALTIES_FEE");
        royaltiesFeeBP = _royaltiesFeeBP;
    }
}
