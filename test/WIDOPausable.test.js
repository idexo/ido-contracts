const { expect } = require('chai');
const WIDOPausable = artifacts.require('WIDOPausable');
const { BN, constants, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');

contract('WIDOPausable', async accounts => {
  let contract;
  const [relayer, alice, bob, carol] = accounts;

  before(async () => {
    contract = await WIDOPausable.new();
  });

  describe('Token', async () => {
    it('expect to mint and burn', async () => {
      await contract.setRelayer(relayer);
      expectEvent(
        await contract.mint(alice, web3.utils.toWei(new BN(100)), {from: relayer}),
        'Transfer'
      );
      expectEvent(
        await contract.burn(alice, web3.utils.toWei(new BN(100)), {from: relayer}),
        'Transfer'
      );
      await contract.balanceOf(alice).then(res => {
        expect(res.toString()).to.eq('0');
      });
    });
    describe('reverts if', async () => {
      it('non-owner call setRelayer', async () => {
        await expectRevert(
          contract.setRelayer(bob, {from: bob}),
          'Ownable: CALLER_NO_OWNER'
        );
      });
      it('non-relayer call mint/burn', async () => {
        await expectRevert(
          contract.mint(alice, web3.utils.toWei(new BN(100)), {from: bob}),
          'WIDOPausable: CALLER_NO_RELAYER'
        );
        await expectRevert(
          contract.burn(alice, web3.utils.toWei(new BN(100)), {from: bob}),
          'WIDOPausable: CALLER_NO_RELAYER'
        );
      });
    });
  });

  describe('#Ownership', async () => {
    it('should transfer ownership', async () => {
      await contract.transferOwnership(bob);
      await contract.acceptOwnership({from: bob});
      expect(await contract.owner()).to.eq(bob);
    });
    describe('reverts if', async () => {
      it('non-owner call transferOwnership', async () => {
        await expectRevert(
          contract.transferOwnership(bob, {from: carol}),
          'Ownable: CALLER_NO_OWNER'
        );
      });
      it('call transferOwnership with zero address', async () => {
        await expectRevert(
          contract.transferOwnership(constants.ZERO_ADDRESS, {from: bob}),
          'Ownable: INVALID_ADDRESS'
        );
      });
      it('non new owner call acceptOwnership', async () => {
        await contract.transferOwnership(alice, {from: bob});
        await expectRevert(
          contract.acceptOwnership({from: carol}),
          'Ownable: CALLER_NO_NEW_OWNER'
        );
      })
    });
  });
});
