// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Ownable.sol";

contract Whitelist is Ownable {
  // wallet address => whitelisted status
  mapping(address => bool) public whitelist;

  event AddedWhitelist(address account);
  event RemovedWhitelist(address account);

  modifier onlyWhitelist() {
    require(whitelist[msg.sender], "Whitelist: CALLER_NO_WHITELIST");
    _;
  }

  /**
   * @dev Add wallet to whitelist
   * `_account` must not be zero address
   */
  function addWhitelist(address[] memory accounts) public onlyOwner {
    for (uint256 i = 0; i < accounts.length; i++) {
      if (accounts[i] != address(0) && !whitelist[accounts[i]]) {
        whitelist[accounts[i]] = true;

        emit AddedWhitelist(accounts[i]);
      }
    }
  }

  /**
   * @dev Remove wallet from whitelist
   */
  function removeWhitelist(address[] memory accounts) public onlyOwner {
    for (uint256 i = 0; i < accounts.length; i++) {
      if (whitelist[accounts[i]]) {
        whitelist[accounts[i]] = false;

        emit RemovedWhitelist(accounts[i]);
      }
    }
  }
}
