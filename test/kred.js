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
            "WIDO: CALLER_NO_OWNER"
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

    describe("#Ownership", async () => {
      it("should transfer ownership", async () => {
        await token.transferOwnership(bob);
        await token.acceptOwnership({ from: bob });
        expect(await token.owner()).to.eq(bob);
      });
      describe("reverts if", async () => {
        it("non-owner call transferOwnership", async () => {
          await expectRevert(
            token.transferOwnership(bob, { from: carol }),
            "WIDO: CALLER_NO_OWNER"
          );
        });
        it("call transferOwnership with zero address", async () => {
          await expectRevert(
            token.transferOwnership(constants.ZERO_ADDRESS, { from: bob }),
            "WIDO: INVALID_ADDRESS"
          );
        });
        it('non owner call renounceOwnership', async () => {
          await expectRevert(
            token.renounceOwnership({from: darren}),
            "WIDO: CALLER_NO_OWNER"
          );
        });
        it("non new owner call acceptOwnership", async () => {
          await token.transferOwnership(alice, { from: bob });
          await expectRevert(
            token.acceptOwnership({ from: carol }),
            "WIDO: CALLER_NO_NEW_OWNER"
          );
          expectEvent(
            await token.renounceOwnership({from: bob}),
            'OwnershipTransferred'
          )
        });
      });
    });
  });
}

module.exports = { testToken };
