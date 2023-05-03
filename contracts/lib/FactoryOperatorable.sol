// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract FactoryOperatorable is Ownable2Step, AccessControl {
  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  modifier onlyOperator() {
    require(hasRole(OPERATOR_ROLE, msg.sender), "Operatorable: CALLER_NO_OPERATOR_ROLE");
    _;
  }

  modifier onlyAdmin() {
    require(hasRole(ADMIN_ROLE, msg.sender), "Operatorable: CALLER_NO_ADMIN_ROLE");
    _;
  }

  constructor(address _admin, address _operator) {
    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(OPERATOR_ROLE, _operator);
  }

  function addOperator(address _account) public onlyAdmin {
    grantRole(OPERATOR_ROLE, _account);
  }

  function removeOperator(address _account) public onlyAdmin {
    revokeRole(OPERATOR_ROLE, _account);
  }

  function checkOperator(address _account) public view returns (bool) {
    return hasRole(OPERATOR_ROLE, _account);
  }
}
