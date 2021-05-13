// import IDO from 'IDO';
const { expect, assert} = require('chai');
const truffleAssert = require('truffle-assertions');

const IDO = artifacts.require('IDO');

contract('::IDO', async accounts => {
  let token;
  const [alice, bob, carl] = accounts;
  const name = 'Idexo Token';
  const symbol = 'IDO';

  beforeEach(async () => {
    token = await IDO.new(name, symbol, {from: alice});
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
          'revert IDO: not admin'
        );
      });
      it('remove operator by non-admin', async () => {
        await token.addOperator(bob);
        await truffleAssert.reverts(
          token.removeOperator(bob, {from: bob}),
          'revert IDO: not admin'
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
      await token.unpause({from: bob});
      expect(await token.paused()).to.eq(false);
    });
    describe('reverts if', async () => {
      it('pause/unpause by non-pauser', async () => {
        await token.addPauser(bob);
        await token.addOperator(carl);
        await truffleAssert.reverts(
          token.pause({from: carl}),
          'revert IDO: not pauser'
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
      await token.mint(alice, 500, {from: bob});
      await token.balanceOf(alice).then(balance => {
        expect(balance.toString()).to.eq('500');
      });
      await truffleAssert.reverts(
        token.mint(alice, 100 * 1000 * 1000, {from: bob}),
        'revert ERC20Capped: cap exceeded'
      );
    });
    describe('reverts if', async () => {
      it('mint a new token by non-operator', async () => {
        await truffleAssert.reverts(
          token.mint(alice, 10, {from: bob}),
          'revert IDO: not operator'
        );
      });
    });
  });

  describe('Ownership', async () => {
    it('should transfer only by admin', async () => {
      await token.transferOwnership(bob);
      expect(await token.owner()).to.eq(bob);
    });
    describe('reverts if', async () => {
      it('transfer by non-admin', async () => {
        await truffleAssert.reverts(
          token.transferOwnership(bob, {from: bob}),
          'revert IDO: not admin'
        );
      });
    });
  });
});
