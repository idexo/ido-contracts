function testToken(contractName, contractPath) {
  contract("::" + contractName, async (accounts) => {
    let token;
    const [alice, bob, carol, darren] = accounts;

    const { expect } = require("chai");
    const { constants, expectEvent, expectRevert, } = require("@openzeppelin/test-helpers");
    const contract = artifacts.require(contractPath);

    describe("#Role", async () => {
      it("should set relayer", async () => {
        token = await contract.new()
        expectEvent(
          await token.setRelayer(bob),
          'RelayerAddressChanged'
        )
      });
      describe("reverts if", async () => {
        it("set relayer by non-owner", async () => {
          await expectRevert(
            token.setRelayer(bob, { from: bob }),
            "Ownable: caller is not the owner"
          );
        });
      });
    });

    describe("#Mint", async () => {
      it("should mint", async () => {
        expectEvent(
          await token.mint(bob, 1, { from: bob }),
          'Transfer'
        )
      });
      describe("reverts if", async () => {
        it("mint by non relayer", async () => {
          await expectRevert(
            token.mint(bob, 1, { from: darren }),
            "WIDO: CALLER_NO_RELAYER"
          );
        });
      });
    });

    describe("#Burn", async () => {
      it("should mint", async () => {
        expectEvent(
          await token.burn(bob, 1, { from: bob }),
          'Transfer'
        )
      });
      describe("reverts if", async () => {
        it("mint by non relayer", async () => {
          await expectRevert(
            token.burn(bob, 1, { from: darren }),
            "WIDO: CALLER_NO_RELAYER"
          );
        });
      });
    });

    describe("#Chainid", async () => {
        it("should get chainid", async () => {
          expect(await token.getChainId()).to.exist;
        });
      });
  });
}

module.exports = { testToken };
