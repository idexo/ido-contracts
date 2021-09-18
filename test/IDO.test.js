// Initiate `ownerPrivateKey` with the first account private key on test evm

const { expect, assert} = require('chai');
const truffleAssert = require('truffle-assertions');
const {
  BN,
  constants,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');
const {
  PERMIT_TYPEHASH,
  getPermitDigest,
  getDomainSeparator,
  sign
} = require('./helpers/signature');

const IDO = artifacts.require('IDO');

contract('::IDO', async accounts => {
  let token;
  const [alice, bob, carol] = accounts;
  const name = 'Idexo Token'; // token name
  let chainId; // buidlerevm chain id
  // this key is from the first address on test evm
  const ownerPrivateKey = Buffer.from('95980b41b3377ca2163e38623f3d11df0d7cd35d121034cde7d389d82508be65', 'hex');

  describe('#Role', async () => {
    it ('should add operator', async () => {
      token = await IDO.new();
      await token.getChainId().then(res => {
        chainId = res.toNumber();
      })

      await token.addOperator(bob);
      expect(await token.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await token.removeOperator(bob);
      expect(await token.checkOperator(bob)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('add operator by non-admin', async () => {
        await expectRevert(
          token.addOperator(bob, {from: bob}),
          'revert IDO: CALLER_NO_OWNER'
        );
      });
      it('remove operator by non-admin', async () => {
        await token.addOperator(bob);
        await expectRevert(
          token.removeOperator(bob, {from: bob}),
          'revert IDO: CALLER_NO_OWNER'
        );
      });
    });
  });

  describe('#pause', async () => {
    it('should be paused/unpaused by operator', async () => {
      await token.pause({from: bob});
      expect(await token.paused()).to.eq(true);
      // Owner can transfer
      await token.transfer(bob, web3.utils.toWei(new BN(500)));
      // Non owner can not transfer
      await expectRevert(
        token.transfer(alice, web3.utils.toWei(new BN(500)), {from: bob}),
        'ERC20Pausable: token transfer while paused'
      );
      await token.unpause({from: bob});
      expect(await token.paused()).to.eq(false);
      // Now everyone can transfer
      await token.transfer(alice, web3.utils.toWei(new BN(500)), {from: bob});
    });
    describe('reverts if', async () => {
      it('pause/unpause by non-operator', async () => {
        await expectRevert(
          token.pause({from: carol}),
          'IDO: CALLER_NO_OPERATOR_ROLE'
        );
      });
    });
  });

  describe('#Token', async () => {
    it('totalsupply', async () => {
      await token.balanceOf(alice).then(res => {
        expect(res.toString()).to.eq('100000000000000000000000000');
      });
    });
    it('should permit and approve', async () => {
      // Create the approval request
      const approve = {
        owner: alice,
        spender: bob,
        value: 100,
      };
      // deadline as much as you want in the future
      const deadline = 100000000000000;
      // Get the user's nonce
      const nonce = await token.nonces(alice);
      // Get the EIP712 digest
      const digest = getPermitDigest(name, token.address, chainId, approve, nonce.toNumber(), deadline);
      // Sign it
      // NOTE: Using web3.eth.sign will hash the message internally again which
      // we do not want, so we're manually signing here
      const { v, r, s } = sign(digest, ownerPrivateKey);
      // Approve it
      expectEvent(
        await token.permit(approve.owner, approve.spender, approve.value, deadline, v, r, s),
        'Approval'
      );
    });
  });

  describe('#Ownership', async () => {
    it('should transfer ownership', async () => {
      await token.transferOwnership(bob);
      await token.acceptOwnership({from: bob});
      expect(await token.owner()).to.eq(bob);
    });
    describe('reverts if', async () => {
      it('non-owner call transferOwnership', async () => {
        await expectRevert(
          token.transferOwnership(bob, {from: carol}),
          'IDO: CALLER_NO_OWNER'
        );
      });
      it('call transferOwnership with zero address', async () => {
        await expectRevert(
          token.transferOwnership(constants.ZERO_ADDRESS, {from: bob}),
          'IDO: INVALID_ADDRESS'
        );
      });
      it('non new owner call acceptOwnership', async () => {
        await token.transferOwnership(alice, {from: bob});
        await expectRevert(
          token.acceptOwnership({from: carol}),
          'IDO: CALLER_NO_NEW_OWNER'
        );
      })
    });
  });
});
