const CommunityNFT = artifacts.require("CommunityNFT");

const { expect } = require("chai");
const { expectEvent, expectRevert } = require("@openzeppelin/test-helpers");

contract("CommunityNFT", async (accounts) => {
  let nft;
  const [alice, bob, carol, darren] = accounts;

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
        await nft.mintNFT(darren, { from: bob });
        const ids = await nft.tokenIds();
        expect(await ids.toString()).to.eq("3");
        const balance = await nft.balanceOf(carol);
        expect(await balance.toString()).to.eq("1");
        const tokenId = await nft.getTokenId(carol);
        expect(await tokenId.toString()).to.eq("2");
        await nft.setApprovalForAll(bob, true, {from: carol});
        expectEvent(
          await nft.transferFrom(carol, alice, 2, {from: bob}),
          'Transfer'
        );
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
    });
  });
  // describe("#URI", async () => {
  //   it("should set token URI", async () => {
  //     await nft.mintNFT(carol, { from: bob });
  //     await nft.mintNFT(bob, { from: bob });
  //     const tokenIdAlice = await nft.getTokenId(alice);
  //     const tokenIdCarol = await nft.getTokenId(carol);
  //     const tokenIdBob = await nft.getTokenId(bob);
  //     console.log("Alice: ", tokenIdAlice.toString());
  //     console.log("Carol: ", tokenIdCarol.toString());
  //     console.log("Bob: ", tokenIdBob.toString());
  //     // await nft.setTokenURI(1,"TokenURI");
  //     // expect(await nft.tokenURI(1)).to.eq("https://idexo.io/TokenURI");
  //   });

  // });
});
