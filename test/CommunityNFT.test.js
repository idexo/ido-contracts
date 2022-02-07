const CommunityNFT = artifacts.require("CommunityNFT");

const { expect } = require("chai");
const { expectEvent, expectRevert } = require("@openzeppelin/test-helpers");

contract("CommunityNFT", async (accounts) => {
  let nft;
  const [alice, bob, carol] = accounts;

  before(async () => {
    nft = await CommunityNFT.new("TEST", "T", "https://idexo.io/");
  });

  describe("#Role", async () => {
    it("should add operator", async () => {
      await nft.addOperator(bob);
      expect(await nft.checkOperator(bob)).to.eq(true);
    });
    it("should check operator", async () => {
      await nft.checkOperator(bob);
      expect(await nft.checkOperator(bob)).to.eq(true);
    });
    it("should remove operator", async () => {
      await nft.removeOperator(bob);
      expect(await nft.checkOperator(bob)).to.eq(false);
    });
    describe("reverts if", async () => {
      it("add operator by non-admin", async () => {
        await expectRevert(
          nft.addOperator(bob, { from: bob }),
          "CALLER_NO_ADMIN_ROLE"
        );
      });
      it("remove operator by non-admin", async () => {
        await nft.addOperator(bob);
        await expectRevert(
          nft.removeOperator(bob, { from: bob }),
          "CALLER_NO_ADMIN_ROLE"
        );
      });
    });
  });

  describe("#Mint", async () => {
    it("should mint NFT", async () => {
      await nft.mintNFT(alice, { from: bob });
      const balance = await nft.balanceOf(alice);
      expect(await balance.toString()).to.eq("1");
      const tokenId = await nft.getTokenId(alice);
      expect(await tokenId.toString()).to.eq("1");
    });
    it("should transfer NFT", async () => {
        await nft.mintNFT(carol, { from: bob });
        const balance = await nft.balanceOf(carol);
        expect(await balance.toString()).to.eq("1");
        const tokenId = await nft.getTokenId(carol);
        expect(await tokenId.toString()).to.eq("2");
      });
    describe("reverts if", async () => {
      it("caller no operator role", async () => {
        await expectRevert(
          nft.mintNFT(alice, { from: carol }),
          "CALLER_NO_OPERATOR_ROLE"
        );
      });
      it("account already has nft", async () => {
        await expectRevert(
          nft.mintNFT(alice, { from: bob }),
          "ACCOUNT_ALREADY_HAS_NFT"
        );
      });
      // it("remove operator by non-admin", async () => {
      //   await nft.addOperator(bob);
      //   await expectRevert(
      //     nft.removeOperator(bob, { from: bob }),
      //     "CALLER_NO_ADMIN_ROLE"
      //   );
      // });
    });
  });
  // describe("#URI", async () => {
  //   it("should set token URI", async () => {
  //     await nft.setTokenURI(1,"https://test.uri");
  //     expect(await nft.tokenURI(bob)).to.eq("https://test.uri");
  //   });

  // });
});
