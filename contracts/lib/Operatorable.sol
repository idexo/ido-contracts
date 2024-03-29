// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract Operatorable is Ownable2Step, AccessControl {
  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

  /**
    * @dev Restricted to members of the `operator` role.
    */
  modifier onlyOperator() {
    require(hasRole(OPERATOR_ROLE, msg.sender), "Operatorable: CALLER_NO_OPERATOR_ROLE");
    _;
  }

  constructor() {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(OPERATOR_ROLE, msg.sender);
  }

  /**
    * @dev Add an `_account` to the `operator` role.
    */
  function addOperator(address _account) public onlyOwner {
    grantRole(OPERATOR_ROLE, _account);
  }

  /**
    * @dev Remove an `_account` from the `operator` role.
    */
  function removeOperator(address _account) public onlyOwner {
    revokeRole(OPERATOR_ROLE, _account);
  }

  /**
    * @dev Check if an _account is operator.
    */
  function checkOperator(address _account) public view returns (bool) {
    return hasRole(OPERATOR_ROLE, _account);
  }
}
