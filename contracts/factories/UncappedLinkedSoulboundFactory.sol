//SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../soulbound/UncappedLinkedSoulbound.sol";

contract UncappedLinkedSoulboundFactory {
	event UncappedLinkedSoulboundCreated(address indexed creator, address indexed instance);

	function createUncappedLinkedSoulbound(
		string memory collectionName,
		string memory collectionSymbol,
		string memory collectionBaseURI
	) external returns(address) {
		UncappedLinkedSoulbound newContract = new UncappedLinkedSoulbound(
			collectionName,
			collectionSymbol,
			collectionBaseURI
			);
		newContract.transferOwnership(msg.sender);
		emit UncappedLinkedSoulboundCreated(msg.sender, address(newContract));
		return address(newContract);
	}

}

