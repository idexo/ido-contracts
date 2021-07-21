const { expect, assert} = require('chai');
const truffleAssert = require('truffle-assertions');
const {
  BN,
  constants,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');

const IDO = artifacts.require('IDO');

contract('::IDO', async accounts => {
  let token;
  const [alice, bob, carl] = accounts;
  const decimals = 18;

  beforeEach(async () => {
    token = await IDO.new({from: alice});
  });

  describe('#Role', async () => {
    it ('should add operator', async () => {
      await token.addOperator(bob);
      expect(await token.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await token.addOperator(bob);
      await token.removeOperator(bob);
      expect(await token.checkOperator(bob)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('add operator by non-admin', async () => {
        await truffleAssert.reverts(
          token.addOperator(bob, {from: bob}),
          'revert IDO#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
      it('remove operator by non-admin', async () => {
        await token.addOperator(bob);
        await truffleAssert.reverts(
          token.removeOperator(bob, {from: bob}),
          'revert IDO#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
    });
  });

  describe('#pause', async () => {
    it('should be paused/unpaused by pauser', async () => {
      await token.addPauser(bob);
      await token.addOperator(carl);
      await token.pause({from: bob});
      expect(await token.paused()).to.eq(true);
      await truffleAssert.reverts(
        token.mint(alice, new BN(1000).mul(new BN(10).pow(new BN(decimals)))),
        'revert ERC20Pausable: token transfer while paused'
      );
      await token.unpause({from: bob});
      expect(await token.paused()).to.eq(false);
    });
    describe('reverts if', async () => {
      it('pause/unpause by non-pauser', async () => {
        await token.addPauser(bob);
        await token.addOperator(carl);
        await truffleAssert.reverts(
          token.pause({from: carl}),
          'revert IDO#onlyPauser: CALLER_NO_PAUSER_ROLE'
        );
      });
    });
  });

  describe('#Token', async () => {
    it('should mint a new token by operator', async () => {
      await token.addOperator(bob);
      await token.mint(alice, 10, {from: bob});
      await token.balanceOf(alice).then(balance => {
        expect(balance.toString()).to.eq('10');
      });
    });
    it('shoule not mint when exceeded cap', async () => {
      await token.addOperator(bob);
      await token.mint(alice, new BN(500), {from: bob});
      await token.balanceOf(alice).then(balance => {
        expect(balance.toString()).to.eq('500');
      });
      await truffleAssert.reverts(
        token.mint(alice, new BN(100 * 1000 * 1000).mul(new BN(10).pow(new BN(decimals))), {from: bob}),
        'revert ERC20Capped: cap exceeded'
      );
    });
    describe('reverts if', async () => {
      it('mint a new token by non-operator', async () => {
        await truffleAssert.reverts(
          token.mint(alice, 10, {from: bob}),
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
          token.transferOwnership(bob, {from: carl}),
          'IDO#onlyOwner: CALLER_NO_OWNER'
        );
      });
      it('call transferOwnership with zero address', async () => {
        await expectRevert(
          token.transferOwnership(constants.ZERO_ADDRESS),
          'IDO#transferOwnership: INVALID_ADDRESS'
        );
      });
      it('non new owner call acceptOwnership', async () => {
        await token.transferOwnership(bob);
        await expectRevert(
          token.acceptOwnership({from: carl}),
          'IDO#acceptOwnership: CALLER_NO_NEW_OWNER'
        );
      })
    });
  });
});
