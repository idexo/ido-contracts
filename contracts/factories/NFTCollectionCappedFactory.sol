//SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../nft/StandardCappedNFTCollectionFC.sol";

contract NFTCollectionCappedFactory {
	event StandardCappedNFTCollection(address indexed creator, address indexed instance);

	function createStandardCappedNFTCollection(
		string memory collectionName,
		string memory collectionSymbol,
		string memory collectionBaseURI,
		uint256 cap,
		address admin,
		address operator
	) external returns(address) {
		StandardCappedNFTCollectionFC newContract = new StandardCappedNFTCollectionFC(
			collectionName,
			collectionSymbol,
			collectionBaseURI,
			cap,
			admin,
			operator
			);
		newContract.transferOwnership(msg.sender);
		emit StandardCappedNFTCollection(msg.sender, address(newContract));
		return address(newContract);
	}



}

