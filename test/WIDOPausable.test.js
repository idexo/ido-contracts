const { expect } = require('chai');
const WIDOPausable = artifacts.require('WIDOPausable');
const { BN, constants, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');

contract('WIDOPausable', async accounts => {
  let contract, chainId;
  const [relayer, alice, bob, carol] = accounts;

  before(async () => {
    contract = await WIDOPausable.new();
  });

  describe('Token', async () => {
    it('expect to mint and burn', async () => {
      await contract.getChainId().then(res => {
        expect(res).to.not.null;
        chainId = res.toNumber();
      })
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
          'Ownable: caller is not the owner'
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

  describe('#Blacklist', async () => {
    it('should add to blacklist', async () => {
      expectEvent(
        await contract.addBlacklist([relayer]),
        'AddedBlacklist'
      );
      await expectRevert(
        contract.mint(bob, web3.utils.toWei(new BN(100)), {from: relayer}),
        'WIDOPausable: CALLER_BLACKLISTED'
      );
    });
    it('should remove from blacklist', async () => {
      expectEvent(
        await contract.removeBlacklist([relayer]),
        'RemovedBlacklist'
      );
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
          'Ownable: caller is not the owner'
        );
      });
      it('non new owner call acceptOwnership', async () => {
        await contract.transferOwnership(alice, {from: bob});
        await expectRevert(
          contract.acceptOwnership({from: carol}),
          'Ownable2Step: caller is not the new owner'
        );
      });
      it('non owner call renounceOwnership', async () => {
        await expectRevert(
            contract.renounceOwnership({from: carol}),
          'Ownable: caller is not the owner'
        );
      });
      it('non new owner call acceptOwnership', async () => {
        await contract.transferOwnership(alice, {from: bob});
        await expectRevert(
            contract.acceptOwnership({from: carol}),
          'Ownable2Step: caller is not the new owner'
        );
        expectEvent(
          await contract.renounceOwnership({from: bob}),
          'OwnershipTransferred'
        )
      })
    });
  });
});
