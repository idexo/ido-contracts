const CommunityNFT = artifacts.require("CommunityNFT");

const { expect } = require("chai");
const { expectEvent, expectRevert } = require("@openzeppelin/test-helpers");

contract("CommunityNFT", async (accounts) => {
  let nft;
  const [alice, bob, carol] = accounts;

  before(async () => {
    nft = await CommunityNFT.new( "TEST", "T", "https://idexo.io/" );
  });

  describe("#Role", async () => {
    it("should add operator", async () => {
      await nft.addOperator(bob);
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
});
