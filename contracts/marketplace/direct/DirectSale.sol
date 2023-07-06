// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./DirectSaleNFTs.sol";
import "./BaseRoyaltyNFT.sol";
import "@openzeppelin/contracts/metatx/MinimalForwarder.sol";

contract DirectSale is DirectSaleNFTs {
    using SafeERC20 for IERC20;

    constructor(address _purchaseToken, address _trustedForwarder) DirectSaleNFTs(_purchaseToken, _trustedForwarder) {}

    function currentOwner(address _nft, uint256 _tokenID) internal virtual view override returns (address) {
        return BaseRoyaltyNFT(_nft).ownerOf(_tokenID);
    }

    function _purchase(
        address _nft,
        address _tokenOwner,
        address _buyer,
        uint256 _tokenID
    ) internal virtual override {
        require(nftSales[_nft][_tokenID].price != 0, "INVALID_PRICE");
        uint256 nftSaleId = nftIdSaleId[_nft][_tokenID];
        NFTSaleInfo memory nftSale = salesById[nftSaleId];

        (address royaltyCollector, uint256 royaltyFee) = BaseRoyaltyNFT(_nft).royaltyInfo(_tokenID, nftSales[_nft][_tokenID].price);
        nftSales[_nft][_tokenID].isOpenForSale = false;
        nftSale.isOpenForSale = false;

        IERC20(purchaseToken).safeTransferFrom(_buyer, BaseRoyaltyNFT(_nft).royaltiesCollector(), royaltyFee);
        IERC20(purchaseToken).safeTransferFrom(_buyer, _tokenOwner, nftSales[_nft][_tokenID].price - royaltyFee);
        BaseRoyaltyNFT(_nft).safeTransferFrom(_tokenOwner, _buyer, _tokenID);
        

        emit Purchased(_nft, _tokenID, _tokenOwner, _buyer);
    }
}