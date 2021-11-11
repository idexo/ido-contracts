// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./RelayManager2.sol";

contract RelayManager2Batch is RelayManager2 {
  using SafeERC20 for IWIDO;

  constructor(IWIDO _wIDO, uint256 _adminFee) RelayManager2(_wIDO, _adminFee) { }

  /**
    * @dev Batch version of {send}
    */
  function sendBatch(
    address[] memory receivers,
    uint256[] memory amounts,
    bytes32[] memory depositHashes,
    uint256 gasPrice
  ) external nonReentrant onlyOperator {
    require(receivers.length == amounts.length && amounts.length == depositHashes.length, "RelayManager2Batch: PARAMS_LENGTH_MISMATCH");
    for (uint256 i = 0; i < receivers.length; i++) {
      _send(receivers[i], amounts[i], depositHashes[i], gasPrice);
    }
  }
}
