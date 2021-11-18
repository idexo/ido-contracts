// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

contract Ownable {
  // Contract owner address
  address public owner;
  // Proposed new contract owner address
  address public newOwner; 

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  constructor() {
    owner = msg.sender;
    emit OwnershipTransferred(address(0), msg.sender);
  }

  /****************************|
	|          Ownership         |
	|___________________________*/

	/**
		* @dev Throws if called by any account other than the owner.
		*/
	modifier onlyOwner() {
			require(owner == msg.sender, "Ownable: CALLER_NO_OWNER");
			_;
	}

	/**
		* @dev Leaves the contract without owner. It will not be possible to call
		* `onlyOwner` functions anymore. Can only be called by the current owner.
		*
		* NOTE: Renouncing ownership will leave the contract without an owner,
		* thereby removing any functionality that is only available to the owner.
		*/
	function renounceOwnership() external onlyOwner {
		emit OwnershipTransferred(owner, address(0));
		owner = address(0);
	}

	/**
		* @dev Transfer the contract ownership.
		* The new owner still needs to accept the transfer.
		* can only be called by the contract owner.
		*/
	function transferOwnership(address _newOwner) external onlyOwner {
		require(_newOwner != address(0), "Ownable: INVALID_ADDRESS");
		require(_newOwner != owner, "Ownable: OWNERSHIP_SELF_TRANSFER");
		newOwner = _newOwner;
	}

	/**
		* @dev The new owner accept an ownership transfer.
		*/
	function acceptOwnership() external {
		require(msg.sender == newOwner, "Ownable: CALLER_NO_NEW_OWNER");
		emit OwnershipTransferred(owner, newOwner);
		owner = newOwner;
		newOwner = address(0);
	}
}