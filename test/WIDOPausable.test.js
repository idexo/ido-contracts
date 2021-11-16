const { expect } = require('chai');
const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const WIDOPausable = artifacts.require('WIDOPausable');

contract('::WIDOPausable', async accounts => {
  let token;
  const [alice, bob, carol, relayer] = accounts;
  let chainId; // buidlerevm chain id

  describe('#Token', async () => {
    it('mint, burn', async () => {
      token = await WIDOPausable.new();
      await token.getChainId().then(res => {
        chainId = res.toNumber();
      })
      await token.setRelayer(relayer);
      expectEvent(
        await token.mint(alice, web3.utils.toWei(new BN(100)), {from: relayer}),
        'Transfer'
      );
      expectEvent(
        await token.burn(alice, web3.utils.toWei(new BN(10)), {from: relayer}),
        'Transfer'
      );
    });
  });

  describe("#pause", async () => {
    it("should be paused/unpaused by owner", async () => {
      await token.transferOwnership(alice);
      await token.acceptOwnership({ from: alice });
      await token.pause({ from: alice });
      expect(await token.paused()).to.eq(true);
      // Owner can transfer
      await token.transfer(bob, web3.utils.toWei(new BN(50)), { from: alice });
      // Non owner can not transfer
      await expectRevert(
        token.transfer(alice, web3.utils.toWei(new BN(50)), { from: bob }),
        "ERC20Pausable: token transfer while paused"
      );
      await token.unpause({ from: alice });
      expect(await token.paused()).to.eq(false);
      // Now everyone can transfer
      await token.transfer(alice, web3.utils.toWei(new BN(50)), { from: bob });
    });
    describe("reverts if", async () => {
      it("pause/unpause by non-owner", async () => {
        await expectRevert(
          token.pause({ from: carol }),
          "WIDO: CALLER_NO_OWNER"
        );
      });
    });
  });
});
