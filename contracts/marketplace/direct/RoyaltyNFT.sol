// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../lib/Error.sol";
import "./BaseRoyaltyNFT.sol";

contract RoyaltyNFT is BaseRoyaltyNFT {
  // Royalties fee in Basis Points
  uint8 public royaltiesFeeBP;

  constructor(
    string memory _name,
    string memory _symbol,
    string memory _baseTokenURI,
    address _royaltiesCollector,
    uint8 _royaltiesFeeBP
  ) BaseRoyaltyNFT(_name, _symbol, _baseTokenURI, _royaltiesCollector) {
    if (_royaltiesFeeBP > 1000) revert InvalidRoyaltiesFee();
    royaltiesFeeBP = _royaltiesFeeBP;
  }

  /**
    * @dev Set `royaltiesFeeBP`
    * Only `owner` can call
    * `_royaltiesFeeBP` must not be greater than 1000
   */
  function setRoyaltiesFeeBP(uint8 _royaltiesFeeBP) external onlyOwner {
    if (_royaltiesFeeBP > 1000) revert InvalidRoyaltiesFee();
    royaltiesFeeBP = _royaltiesFeeBP;
  }
}
