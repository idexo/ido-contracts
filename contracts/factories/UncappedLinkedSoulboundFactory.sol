//SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../soulbound/UncappedLinkedSoulboundFC.sol";

contract UncappedLinkedSoulboundFactory {
	event UncappedLinkedSoulboundCreated(address indexed creator, address indexed instance);

	function createUncappedLinkedSoulbound(
		string memory collectionName,
		string memory collectionSymbol,
		string memory collectionBaseURI,
		address admin,
		address operator
	) external returns(address) {
		UncappedLinkedSoulboundFC newContract = new UncappedLinkedSoulboundFC(
			collectionName,
			collectionSymbol,
			collectionBaseURI,
			admin,
			operator
			);
		newContract.transferOwnership(msg.sender);
		emit UncappedLinkedSoulboundCreated(msg.sender, address(newContract));
		return address(newContract);
	}




}

