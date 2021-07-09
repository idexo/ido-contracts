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
  const stakeTokenName = 'Idexo Stake Token';
  const stakeTokenSymbol = 'IDS';
  const erc20Name = 'USD Tether';
  const erc20Symbol = 'USDT';
  const decimals = 18;

  beforeEach(async () => {
    ido = await IDO.new({from: alice});
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
          'revert StakePool#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
      it('remove operator by non-admin', async () => {
        await stakePool.addOperator(bob);
        await truffleAssert.reverts(
          stakePool.removeOperator(bob, {from: bob}),
          'revert StakePool#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
    });
  });

  describe('#Stake', async () => {
    beforeEach(async () => {
      await ido.mint(alice, new BN(4000).mul(new BN(10).pow(new BN(decimals))));
      await ido.approve(stakePool.address, new BN(10000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
    });
    describe('##deposit', async () => {
      it('should deposit', async () => {
        await stakePool.deposit(new BN(2800).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        await stakePool.getStake(1).then(res => {
          expect(res[0].toString()).to.eq('2800000000000000000000');
          expect(res[1].toString()).to.eq('120');
        });
        const aliceIDOBalance = await ido.balanceOf(alice);
        expect(aliceIDOBalance.toString()).to.eq('1200000000000000000000');
      });
      describe('reverts if', async () => {
        it('stake amount is lower than minimum amount', async () => {
          await truffleAssert.reverts(
            stakePool.deposit(new BN(2300).mul(new BN(10).pow(new BN(decimals))), {from: alice}),
            'revert StakePool#deposit: UNDER_MINIMUM_STAKE_AMOUNT'
          );
        });
      });
    });
    describe('##withdraw', async () => {
      it('should withdraw', async () => {
        await stakePool.deposit(new BN(2800).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        await stakePool.withdrawStake(1, new BN(2600).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        await stakePool.getStake(1).then(res => {
          expect(res[0].toString()).to.eq('200000000000000000000');
        });
      });
      describe('reverts if', async () => {
        it('withdraw amount is lower than minimum amount', async () => {
          await stakePool.deposit(new BN(2800).mul(new BN(10).pow(new BN(decimals))), {from: alice});
          await truffleAssert.reverts(
            stakePool.withdrawStake(1, new BN(2300).mul(new BN(10).pow(new BN(decimals))), {from: alice}),
            'revert StakePool#withdraw: UNDER_MINIMUM_STAKE_AMOUNT'
          );
        });
      });
    });
  });

  describe('#Revenue Share', async () => {
    describe('##deposit', async () => {
      beforeEach(async () => {
        await erc20.mint(alice, new BN(10000).mul(new BN(10).pow(new BN(decimals))));
        await erc20.approve(stakePool.address, new BN(10000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        // await stakePool.addOperator(alice);
      });
      it('should deposit', async () => {
        await stakePool.depositRevenueShare(new BN(4000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        await erc20.balanceOf(alice).then(balance => {
          expect(balance.toString()).to.eq('6000000000000000000000');
        });
        await stakePool.deposits(0).then(deposit => {
          expect(deposit.operator).to.eq(alice);
          expect(deposit.amount.toString()).to.eq('4000000000000000000000');
        });
      });
      describe('reverts if', async () => {
        it('deposit amount is 0', async () => {
          await truffleAssert.reverts(
            stakePool.depositRevenueShare(new BN(0), {from: alice}),
            'revert StakePool#depositRevenueShare: ZERO_AMOUNT'
            );
          });
        });
    });
    describe('##distribute', async () => {
      beforeEach(async () => {
        // Deposit stake
        await erc20.mint(alice, new BN(20000).mul(new BN(10).pow(new BN(decimals))));
        await erc20.approve(stakePool.address, new BN(20000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        await erc20.mint(bob, new BN(10000).mul(new BN(10).pow(new BN(decimals))));
        await erc20.approve(stakePool.address, new BN(10000).mul(new BN(10).pow(new BN(decimals))), {from: bob});
        await ido.mint(alice, new BN(10000).mul(new BN(10).pow(new BN(decimals))));
        await ido.approve(stakePool.address, new BN(10000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        await ido.mint(bob, new BN(10000).mul(new BN(10).pow(new BN(decimals))));
        await ido.approve(stakePool.address, new BN(10000).mul(new BN(10).pow(new BN(decimals))), {from: bob});
        // await stakePool.addOperator(alice);
      });
      it('distribute', async () => {
        // After 5 days
        timeTraveler.advanceTime(time.duration.days(5));
        await stakePool.deposit(new BN(3000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        // After 1 day
        timeTraveler.advanceTime(time.duration.days(1));
        await stakePool.deposit(new BN(6000).mul(new BN(10).pow(new BN(decimals))), {from: bob});
        // After 10 days
        timeTraveler.advanceTime(time.duration.days(10));
        await stakePool.depositRevenueShare(new BN(4000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        // After 1 day
        timeTraveler.advanceTime(time.duration.days(1));
        await stakePool.depositRevenueShare(new BN(4500).mul(new BN(10).pow(new BN(decimals))), {from: alice});
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
        await stakePool.depositRevenueShare(new BN(4000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        // After 1 days
        timeTraveler.advanceTime(time.duration.days(1));
        await stakePool.depositRevenueShare(new BN(4500).mul(new BN(10).pow(new BN(decimals))), {from: alice});
        // After 21 days (2 months passed)
        timeTraveler.advanceTime(time.duration.days(15));
        expectEvent(
          await stakePool.distribute({from: alice}),
          'MonthlyDistributed',
          {
            amount: new BN(2122875).mul(new BN(10).pow(new BN(15))),
          }
        );
        await erc20.balanceOf(stakePool.address).then(bn => {
          expect(bn.toString()).to.eq('14877125000000000000000');
        });
        await erc20.balanceOf(alice).then(bn => {
          expect(bn.toString()).to.eq('5122875000000000000000');
        });
        await erc20.balanceOf(bob).then(bn => {
          expect(bn.toString()).to.eq('14245750000000000000000');
        });
      });
    });
  });
});
