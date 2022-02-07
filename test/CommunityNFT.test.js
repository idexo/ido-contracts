const CommunityNFT = artifacts.require("CommunityNFT");

const { expect } = require("chai");
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers");

contract("CommunityNFT", async (accounts) => {
  let nft;
  const [alice, bob, carol, darren] = accounts;

  before(async () => {
    nft = await CommunityNFT.new("TEST", "T", "https://idexo.io/", {
      from: carol,
    });
  });

  describe("#Role", async () => {
    it("should add operator", async () => {
      await nft.addOperator(bob, { from: carol });
      expect(await nft.checkOperator(bob)).to.eq(true);
    });
    it("should check operator", async () => {
      await nft.checkOperator(bob);
      expect(await nft.checkOperator(bob)).to.eq(true);
    });
    it("should remove operator", async () => {
      await nft.removeOperator(bob, { from: carol });
      expect(await nft.checkOperator(bob)).to.eq(false);
    });
    it("supportsInterface", async () => {
      await nft.supportsInterface(`0x00000000`).then((res) => {
        expect(res).to.eq(false);
      });
    });
    describe("reverts if", async () => {
      it("add operator by non-admin", async () => {
        await expectRevert(
          nft.addOperator(bob, { from: bob }),
          "CALLER_NO_ADMIN_ROLE"
        );
      });
      it("remove operator by non-admin", async () => {
        await nft.addOperator(bob, { from: carol });
        await expectRevert(
          nft.removeOperator(bob, { from: bob }),
          "CALLER_NO_ADMIN_ROLE"
        );
      });
    });
  });

  describe("#Mint", async () => {
    it("should mint NFT", async () => {
      expectEvent(await nft.mintNFT(alice, { from: bob }), "NFTCreated");
      const balance = await nft.balanceOf(alice);
      expect(balance.toString()).to.eq("1");
      const tokenId = await nft.getTokenId(alice);
      expect(tokenId.toString()).to.eq("1");
    });
    describe("reverts if", async () => {
      it("caller no operator role", async () => {
        await expectRevert(
          nft.mintNFT(alice, { from: alice }),
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

  describe("#Transfer", async () => {
    it("should transfer NFT", async () => {
      await nft.mintNFT(carol, { from: bob });
      // await nft.mintNFT(darren, { from: bob });
      const ids = await nft.tokenIds();
      expect(ids.toString()).to.eq("2");
      const balance = await nft.balanceOf(carol);
      expect(balance.toString()).to.eq("1");
      let tokenId = await nft.getTokenId(carol);
      expect(tokenId.toString()).to.eq("2");
      await nft.setApprovalForAll(bob, true, { from: carol });
      expectEvent(
        await nft.transferFrom(carol, darren, 2, { from: bob }),
        "Transfer"
      );
      tokenId = await nft.getTokenId(carol);
      expect(tokenId.length).to.eq(0);
      tokenId = await nft.getTokenId(darren);
      expect(tokenId.length).to.eq(1);
    });
    it("should transfer middle NFT", async () => {
      let tokenId = await nft.getTokenId(alice);
      expect(tokenId.length).to.eq(1);
      await nft.setApprovalForAll(bob, true, { from: alice });
      expectEvent(
        await nft.transferFrom(alice, carol, 1, { from: bob }),
        "Transfer"
      );
      tokenId = await nft.getTokenId(alice);
      expect(tokenId.length).to.eq(0);
      // expect(tokenId.toString()).to.eq("2");
      tokenId = await nft.getTokenId(carol);
      expect(tokenId.length).to.eq(1);
      expect(tokenId.toString()).to.eq("1");
    });
    describe("reverts if", async () => {
      it("account already has nft", async () => {
        await nft.setApprovalForAll(bob, true, { from: darren });
        await expectRevert(
          nft.transferFrom(darren, carol, 2, { from: bob }),
          "ACCOUNT_ALREADY_HAS_NFT"
        );
      });
    });
  });

  // describe("#Burn", async () => {
  //   it("should burn NFT", async () => {
  //     await nft.burnNFT(2, { from: bob });
  //     const balance = await nft.balanceOf(darren);
  //     expect(balance.toString()).to.eq("0");
  //     const tokenId = await nft.getTokenId(alice);
  //     expect(tokenId.toString()).to.eq("1");
  //   });
  //   describe("reverts if", async () => {
  //     it("caller no operator role", async () => {
  //       await expectRevert(
  //         nft.mintNFT(alice, { from: alice }),
  //         "CALLER_NO_OPERATOR_ROLE"
  //       );
  //     });
  //     it("account already has nft", async () => {
  //       await expectRevert(
  //         nft.mintNFT(alice, { from: bob }),
  //         "ACCOUNT_ALREADY_HAS_NFT"
  //       );
  //     });
  //   });
  // });

  describe("#URI", async () => {
    it("should set base token URI", async () => {
      // only admin can set BaseURI
      await nft.setBaseURI("https://idexo.com/", { from: carol });
      expect(await nft.baseURI()).to.eq("https://idexo.com/");
    });
    it("should set token URI", async () => {
      await nft.setTokenURI(1, "NewTokenURI", { from: bob });
      expect(await nft.tokenURI(1)).to.eq("https://idexo.com/NewTokenURI");
    });
    describe("reverts if", async () => {
      it("caller no admin role", async () => {
        await expectRevert(
          nft.setBaseURI("https://idexo.com/", { from: bob }),
          "CALLER_NO_ADMIN_ROLE"
        );
      });
    });
  });
  describe("#Earned CRED", async () => {
    it("should update CRED earned", async () => {
      expectEvent(
        await nft.updateNFTCredEarned(1, web3.utils.toWei(new BN(20000)), {
          from: bob,
        }),
        "CREDAdded"
      );
      const checkCred = await nft.credEarned(1);
      expect(web3.utils.fromWei(checkCred.toString(), "ether")).to.eq("20000");
    });
    describe("reverts if", async () => {
      it("caller no operator role", async () => {
        await expectRevert(
          nft.updateNFTCredEarned(1, web3.utils.toWei(new BN(20000)), {
            from: alice,
          }),
          "CALLER_NO_OPERATOR_ROLE"
        );
      });
    });
  });
  describe("#Community Rank", async () => {
    it("should update NFT rank", async () => {
      expectEvent(
        await nft.updateNFTRank(1, "Early Idexonaut", {
          from: bob,
        }),
        "RankUpdated"
      );
      const checkRank = await nft.communityRank(1);
      expect(checkRank).to.eq("Early Idexonaut");
    });
    describe("reverts if", async () => {
      it("caller no operator role", async () => {
        await expectRevert(
          nft.updateNFTRank(1, "Early Idexonaut", {
            from: alice,
          }),
          "CALLER_NO_OPERATOR_ROLE"
        );
      });
    });
  });
});
