// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract Blacklist is Ownable2Step {
  // wallet address => blacklisted status
  mapping(address => bool) blacklist;

  event AddedBlacklist(address account);
  event RemovedBlacklist(address account);

  constructor() { }

  /**
   * @dev Add wallet to blacklist
   * `_account` must not be zero address
   */
  function addBlacklist(address[] memory accounts) public onlyOwner {
    for (uint256 i = 0; i < accounts.length; i++) {
      if (accounts[i] != address(0) && !blacklist[accounts[i]]) {
        blacklist[accounts[i]] = true;

        emit AddedBlacklist(accounts[i]);
      }
    }
  }

  /**
   * @dev Remove wallet from blacklist
   */
  function removeBlacklist(address[] memory accounts) public onlyOwner {
    for (uint256 i = 0; i < accounts.length; i++) {
      if (blacklist[accounts[i]]) {
        blacklist[accounts[i]] = false;

        emit RemovedBlacklist(accounts[i]);
      }
    }
  }
}
