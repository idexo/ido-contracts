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
  const ownerPrivateKey = Buffer.from('f06c0fbe2093c28661914bdc0cd45f2ce4f44476f67f8e94611dadc9a834a455', 'hex');

  describe('#Role', async () => {
    it ('should add operator', async () => {
      token = await IDO.new({from: alice});
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
        await truffleAssert.reverts(
          token.addOperator(bob, {from: bob}),
          'revert IDO#onlyOwner: CALLER_NO_OWNER'
        );
      });
      it('remove operator by non-admin', async () => {
        await token.addOperator(bob);
        await truffleAssert.reverts(
          token.removeOperator(bob, {from: bob}),
          'revert IDO#onlyOwner: CALLER_NO_OWNER'
        );
      });
    });
  });

  describe('#pause', async () => {
    it('should be paused/unpaused by operator', async () => {
      await token.pause({from: bob});
      expect(await token.paused()).to.eq(true);
      await truffleAssert.reverts(
        token.mint(alice, web3.utils.toWei(new BN(1000))),
        'revert ERC20Pausable: token transfer while paused'
      );
      await expectRevert(
        token.transfer(bob, web3.utils.toWei(new BN(500))),
        'ERC20Pausable: token transfer while paused'
      );
      await token.unpause({from: bob});
      expect(await token.paused()).to.eq(false);
    });
    describe('reverts if', async () => {
      it('pause/unpause by non-operator', async () => {
        await truffleAssert.reverts(
          token.pause({from: carol}),
          'IDO#onlyOperator: CALLER_NO_OPERATOR_ROLE'
        );
      });
    });
  });

  describe('#Token', async () => {
    it('should mint a new token by operator', async () => {
      await token.mint(alice, web3.utils.toWei(new BN(1000)), {from: bob});
      await token.balanceOf(alice).then(balance => {
        expect(balance.toString()).to.eq('1000000000000000000000');
      });
    });
    it('shoule not mint when exceeded cap', async () => {
      await token.mint(alice, web3.utils.toWei(new BN(1000)), {from: bob});
      await truffleAssert.reverts(
        token.mint(alice, web3.utils.toWei(new BN(100000000)), {from: bob}),
        'revert ERC20Capped: cap exceeded'
      );
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
      it('mint a new token by non-operator', async () => {
        await truffleAssert.reverts(
          token.mint(alice, web3.utils.toWei(new BN(1000)), {from: carol}),
          'revert IDO#onlyOperator: CALLER_NO_OPERATOR_ROLE'
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
          'IDO#onlyOwner: CALLER_NO_OWNER'
        );
      });
      it('call transferOwnership with zero address', async () => {
        await expectRevert(
          token.transferOwnership(constants.ZERO_ADDRESS, {from: bob}),
          'IDO#transferOwnership: INVALID_ADDRESS'
        );
      });
      it('non new owner call acceptOwnership', async () => {
        await token.transferOwnership(alice, {from: bob});
        await expectRevert(
          token.acceptOwnership({from: carol}),
          'IDO#acceptOwnership: CALLER_NO_NEW_OWNER'
        );
      })
    });
  });
});
