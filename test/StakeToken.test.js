const { Contract } = require('@ethersproject/contracts');
const { expect, assert} = require('chai');
const truffleAssert = require('truffle-assertions');
const {
  BN,
  constants,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');

const StakeToken = artifacts.require('StakeToken');

contract('::StakeToken', async accounts => {
  let token;
  const [alice, bob, carl] = accounts;
  const name = 'Idexo Stake Token';
  const symbol = 'IDS';
  const decimals = 18;
  const timestamp1 = Math.floor(new Date().getTime() / 1000);

  beforeEach(async () => {
    token = await StakeToken.new(name, symbol, {from: alice});
  });

  describe('#multiplier', async () => {
    it('should get multiplier', async () => {
      await token.mint(bob, new BN(250).mul(new BN(10).pow(new BN(decimals))), timestamp1);
      await token.getMultiplier().then(multiplier => {
        expect(multiplier.toNumber()).to.eq(120);
      });
    });
  });

  describe('#NFT', async () => {
    describe('##mint', async () => {
      it('should mint', async () => {
        await token.mint(bob, new BN(250).mul(new BN(10).pow(new BN(decimals))), timestamp1);
        await token.stakes(1).then(stake => {
          expect(stake.amount.toString()).to.eq('250000000000000000000');
          expect(stake.multiplier.toNumber()).to.eq(120);
          expect(stake.depositedAt.toNumber()).to.eq(timestamp1);
        });
      });
      describe('reverts if', async () => {
        it('mint amount is 0', async () => {
          await truffleAssert.reverts(
            token.mint(bob, 0, timestamp1),
            'revert StakeToken#mint: ZERO_AMOUNT'
          );
        });
      });
    });

    describe('##burn', async () => {
      it('should burn', async () => {
        await token.mint(bob, new BN(250).mul(new BN(10).pow(new BN(decimals))), timestamp1);
        await token.burn(1);
      });
      describe('reverts if', async () => {
        it('burn stake that is not found', async () => {
          await truffleAssert.reverts(
            token.burn(1),
            'revert StakeToken#burn: STAKE_NOT_FOUND'
          );
        });
      });
    });
  });
});
