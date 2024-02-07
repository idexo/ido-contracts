// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract FactoryOperatorable is Ownable2Step {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    mapping(bytes32 => mapping(address => bool)) private _roles;

    modifier onlyOperator() {
        require(_roles[OPERATOR_ROLE][msg.sender], "Operatorable: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    modifier onlyAdmin() {
        require(_roles[ADMIN_ROLE][msg.sender], "Operatorable: CALLER_NO_ADMIN_ROLE");
        _;
    }

    constructor(address _admin, address _operator) {
        _roles[ADMIN_ROLE][_admin] = true;
        _roles[OPERATOR_ROLE][_operator] = true;
    }

    function addOperator(address _account) public onlyAdmin {
        _roles[OPERATOR_ROLE][_account] = true;
    }

    function removeOperator(address _account) public onlyAdmin {
        _roles[OPERATOR_ROLE][_account] = false;
    }

    function checkOperator(address _account) public view returns (bool) {
        return _roles[OPERATOR_ROLE][_account];
    }

    function isAdmin(address _account) public view returns (bool) {
        return _roles[ADMIN_ROLE][_account];
    }
}
