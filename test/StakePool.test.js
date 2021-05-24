const { expect, assert} = require('chai');
const truffleAssert = require('truffle-assertions');
const time = require('./helpers/time');
const timeTraveler = require('ganache-time-traveler');
const {
  BN,           // Big Number support
  constants,    // Common constants, like the zero address and largest integers
  expectEvent,  // Assertions for emitted events
  expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers');

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
      beforeEach(async () => {
        await erc20.mint(alice, 10000);
        await erc20.approve(stakePool.address, 10000, {from: alice});
        await stakePool.addOperator(alice);
      });
      it('should deposit', async () => {
        await stakePool.depositRevenueShare(4000, {from: alice});
        await erc20.balanceOf(alice).then(balance => {
          expect(balance.toNumber()).to.eq(6000);
        });
        // expect(await erc20.balanceOf(alice)).to.equal(BigNumber.from(6000));
        await stakePool.deposits(0).then(deposit => {
          expect(deposit.operator).to.eq(alice);
          expect(deposit.amount.toNumber()).to.eq(4000);
        });
      });
      describe('reverts if', async () => {
        it('deposit amount is 0', async () => {
          await truffleAssert.reverts(
            stakePool.depositRevenueShare(0, {from: alice}),
            'revert StakePool: amount should not be zero'
            );
          });
        });
    });
    describe('##distribute', async () => {
      beforeEach(async () => {
        // Deposit stake
        await erc20.mint(alice, 20000);
        await erc20.approve(stakePool.address, 20000, {from: alice});
        await erc20.mint(bob, 10000);
        await erc20.approve(stakePool.address, 10000, {from: bob});
        await ido.mint(alice, 10000);
        await ido.approve(stakePool.address, 10000, {from: alice});
        await ido.mint(bob, 10000);
        await ido.approve(stakePool.address, 10000, {from: bob});
        await stakePool.addOperator(alice);
      });
      it('asdf', async () => {
        // After 5 days
        timeTraveler.advanceTime(time.duration.days(5));
        await stakePool.deposit(3000, {from: alice});
        // After 1 day
        timeTraveler.advanceTime(time.duration.days(1));
        await stakePool.deposit(6000, {from: bob});
        // After 10 days
        timeTraveler.advanceTime(time.duration.days(10));
        await stakePool.depositRevenueShare(4000, {from: alice});
        // After 1 day
        timeTraveler.advanceTime(time.duration.days(1));
        await stakePool.depositRevenueShare(4500, {from: alice});
        // After 15 days (1 month passed)
        timeTraveler.advanceTime(time.duration.days(15));
        expectEvent(
          await stakePool.distribute({from: alice}),
          'MonthlyDistributed',
          {
            amount: new BN(0),
          }
        );
        // After 10 days
        timeTraveler.advanceTime(time.duration.days(10));
        await stakePool.depositRevenueShare(4000, {from: alice});
        // After 1 days
        timeTraveler.advanceTime(time.duration.days(1));
        await stakePool.depositRevenueShare(4500, {from: alice});
        // After 21 days (2 months passed)
        timeTraveler.advanceTime(time.duration.days(15));
        expectEvent(
          await stakePool.distribute({from: alice}),
          'MonthlyDistributed',
          {
            amount: new BN(2122),
          }
        );
        await erc20.balanceOf(stakePool.address).then(bn => {
          expect(bn.toNumber()).to.eq(14878);
        });
        await erc20.balanceOf(alice).then(bn => {
          expect(bn.toNumber()).to.eq(3707);
        });
        await erc20.balanceOf(bob).then(bn => {
          expect(bn.toNumber()).to.eq(11415);
        });
      });
    });
  });
});
