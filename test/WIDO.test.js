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

const WIDO = artifacts.require('WIDO');

contract('::WIDO', async accounts => {
  let token;
  const [alice, bob, carol, relayer] = accounts;
  const name = 'Wrapped Idexo Token'; // token name
  let chainId; // buidlerevm chain id
  // this key is from the first address on test evm
  const ownerPrivateKey = Buffer.from('01246b5dca23b6a21a3b0b59205bb57b8e5ffbe2204e2d76c67ea6459f505a51', 'hex');

  describe('#Role', async () => {
    it ('should add operator', async () => {
      token = await WIDO.new();
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
          'WIDO: CALLER_NO_OWNER'
        );
      });
      it('remove operator by non-admin', async () => {
        await token.addOperator(bob);
        await expectRevert(
          token.removeOperator(bob, {from: bob}),
          'WIDO: CALLER_NO_OWNER'
        );
      });
    });
  });

  describe('#pause', async () => {
    it('should be paused/unpaused by operator', async () => {
      await token.pause({from: bob});
      expect(await token.paused()).to.eq(true);
      await expectRevert(
        token.transfer(bob, web3.utils.toWei(new BN(500))),
        'ERC20Pausable: token transfer while paused'
      );
      await token.unpause({from: bob});
      expect(await token.paused()).to.eq(false);
    });
    describe('reverts if', async () => {
      it('pause/unpause by non-operator', async () => {
        await expectRevert(
          token.pause({from: carol}),
          'WIDO: CALLER_NO_OPERATOR_ROLE'
        );
      });
    });
  });

  describe('#Token', async () => {
    it('mint, burn', async () => {
      await token.setRelayer(relayer);
      expectEvent(
        await token.mint(alice, web3.utils.toWei(new BN(100)), {from: relayer}),
        'Transfer'
      );
      expectEvent(
        await token.burn(alice, web3.utils.toWei(new BN(100)), {from: relayer}),
        'Transfer'
      );
      await token.balanceOf(alice).then(res => {
        expect(res.toString()).to.eq('0');
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
    describe('reverts if', async () => {
      it('non-owner call setRelayer', async () => {
        await expectRevert(
          token.setRelayer(bob, {from: bob}),
          'WIDO: CALLER_NO_OWNER'
        );
      });
      it('non-relayer call mint/burn', async () => {
        await expectRevert(
          token.mint(alice, web3.utils.toWei(new BN(100)), {from: bob}),
          'WIDO: CALLER_NO_RELAYER'
        );
        await expectRevert(
          token.burn(alice, web3.utils.toWei(new BN(100)), {from: bob}),
          'WIDO: CALLER_NO_RELAYER'
        );
      });
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
          'WIDO: CALLER_NO_OWNER'
        );
      });
      it('call transferOwnership with zero address', async () => {
        await expectRevert(
          token.transferOwnership(constants.ZERO_ADDRESS, {from: bob}),
          'WIDO: INVALID_ADDRESS'
        );
      });
      it('non new owner call acceptOwnership', async () => {
        await token.transferOwnership(alice, {from: bob});
        await expectRevert(
          token.acceptOwnership({from: carol}),
          'WIDO: CALLER_NO_NEW_OWNER'
        );
      })
    });
  });
});
