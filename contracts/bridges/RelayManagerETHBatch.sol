// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./RelayManagerETH.sol";

contract RelayManagerETHBatch is RelayManagerETH {
  using SafeERC20 for IERC20;

  constructor(IERC20 _ido, uint256 _adminFee) RelayManagerETH(_ido, _adminFee) { }

  /**
    * @dev Batch version of {send}
    */
  function sendBatch(
    address[] memory receivers,
    uint256[] memory amounts,
    bytes32[] memory depositHashes,
    uint256 gasPrice
  ) external nonReentrant onlyOperator {
    require(receivers.length == amounts.length && amounts.length == depositHashes.length, "RelayManagerETHBatch: PARAMS_LENGTH_MISMATCH");
    for (uint256 i = 0; i < receivers.length; i++) {
      _send(receivers[i], amounts[i], depositHashes[i], gasPrice);
    }
  }
}
