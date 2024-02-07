//SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../staking/StakePoolFlexLockFC.sol";

contract StakePoolFactory {
	event StakePoolFlexLockCreated(address indexed creator, address indexed instance);

	function createStakePoolFlexLock(
		string memory collectionName,
		string memory collectionSymbol,
		string memory collectionBaseURI,
		uint256 minStakeAmount_,
		IERC20 depositToken_,
		address rewardToken_,
		address admin,
		address operator
	) external returns(address) {
		StakePoolFlexLockFC newContract = new StakePoolFlexLockFC(
			collectionName,
			collectionSymbol,
			collectionBaseURI,
			minStakeAmount_,
			depositToken_,
			rewardToken_,
			admin,
			operator
			);
		newContract.transferOwnership(msg.sender);
		emit StakePoolFlexLockCreated(msg.sender, address(newContract));
		return address(newContract);
	}



}

