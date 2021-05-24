const { expect, assert} = require('chai');
const truffleAssert = require('truffle-assertions');

const StakePool = artifacts.require('StakePool');
const ERC20 = artifacts.require('ERC20Mock');
const IDO = artifacts.require('IDO');

contract('::StakePool', async accounts => {
  let stakePool;
  let ido;
  let erc20;

  const [alice, bob, carl] = accounts;
  const idoName = 'Idexo Token';
  const idoSymbol = 'IDO';
  const stakeTokenName = 'Idexo Stake Token';
  const stakeTokenSymbol = 'IDS';
  const erc20Name = 'USD Tether';
  const erc20Symbol = 'USDT';

  beforeEach(async () => {
    ido = await IDO.new(idoName, idoSymbol, {from: alice});
    erc20 = await ERC20.new(erc20Name, erc20Symbol, {from: alice});
    stakePool = await StakePool.new(stakeTokenName, stakeTokenSymbol, ido.address, erc20.address, {from: alice});
  });

  describe('#Role', async () => {
    it ('should add operator', async () => {
      await stakePool.addOperator(bob);
      expect(await stakePool.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await stakePool.addOperator(bob);
      await stakePool.removeOperator(bob);
      expect(await stakePool.checkOperator(bob)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('add operator by non-admin', async () => {
        await truffleAssert.reverts(
          stakePool.addOperator(bob, {from: bob}),
          'revert StakePool: not admin'
        );
      });
      it('remove operator by non-admin', async () => {
        await stakePool.addOperator(bob);
        await truffleAssert.reverts(
          stakePool.removeOperator(bob, {from: bob}),
          'revert StakePool: not admin'
        );
      });
    });
  });

  describe('#Stake', async () => {
    beforeEach(async () => {
      await ido.mint(alice, 4000);
      await ido.approve(stakePool.address, 10000, {from: alice});
    });
    describe('##deposit', async () => {
      it('should deposit', async () => {
        await stakePool.deposit(2800, {from: alice});
        await stakePool.stakes(1).then(stake => {
          expect(stake.amount.toNumber()).to.eq(2800);
          expect(stake.multiplier.toNumber()).to.eq(120);
        });
        const aliceIDOBalance = await ido.balanceOf(alice);
        expect(aliceIDOBalance.toNumber()).to.eq(1200);
      });
      describe('reverts if', async () => {
        it('stake amount is lower than minimum amount', async () => {
          await truffleAssert.reverts(
            stakePool.deposit(2300, {from: alice}),
            'revert StakePool: under minium stake amount'
          );
        });
      });
    });
    describe('##withdraw', async () => {
      it('should withdraw', async () => {
        await stakePool.deposit(2800, {from: alice});
        await stakePool.withdraw(1, 2600, {from: alice});
        await stakePool.stakes(1).then(stake => {
          expect(stake.amount.toNumber()).to.eq(200);
        });
      });
      describe('reverts if', async () => {
        it('withdraw amount is lower than minimum amount', async () => {
          await stakePool.deposit(2800, {from: alice});
          await truffleAssert.reverts(
            stakePool.withdraw(1, 2300, {from: alice}),
            'revert StakePool: under minium stake amount'
          );
        });
      });
    });
  });

  describe('#Revenue Share', async () => {
    describe('##deposit', async () => {
      it('should deposit', async () => {
        await stakePool.addOperator(alice);

      });
    });
  });
});
