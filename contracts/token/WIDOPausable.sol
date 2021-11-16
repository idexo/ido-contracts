// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./WIDO.sol";
import "../lib/Blacklist.sol";

contract WIDOPausable is WIDO, Blacklist {
  constructor() { }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override {
    require(!blacklist[msg.sender], "WIDOPausable: CALLER_BLACKLISTED");
    super._beforeTokenTransfer(from, to, amount);
  }
}
