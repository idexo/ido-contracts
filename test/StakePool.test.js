const { expect, assert} = require('chai');
const time = require('./helpers/time');
const timeTraveler = require('ganache-time-traveler');
const {
  BN,           // Big Number support
  constants,    // Common constants, like the zero address and largest integers
  expectEvent,  // Assertions for emitted events
  expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers');

const StakePool = artifacts.require('StakePool');
const ERC20Mock = artifacts.require('ERC20Mock');
const ERC20Mock6 = artifacts.require('ERC20Mock6');

contract('::StakePool', async accounts => {
  let stakePool;
  let ido;
  let usdt;

  const [alice, bob, carol] = accounts;
  const stakeTokenName = 'Idexo Stake Token';
  const stakeTokenSymbol = 'IDS';

  before(async () => {
    usdt = await ERC20Mock6.new('USDT Mock', 'USDT', {from: alice});
    ido = await ERC20Mock.new('Idexo Token', 'IDO', {from: alice});
    stakePool = await StakePool.new(stakeTokenName, stakeTokenSymbol, ido.address, usdt.address, {from: alice});
    await stakePool.addOperator(bob);
  });

  describe('#Role', async () => {
    it ('should add operator', async () => {
      expect(await stakePool.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await stakePool.removeOperator(bob);
      expect(await stakePool.checkOperator(bob)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('add operator by non-admin', async () => {
        await expectRevert(
          stakePool.addOperator(bob, {from: bob}),
          'Ownable: caller is not the owner'
        );
      });
      it('remove operator by non-admin', async () => {
        await stakePool.addOperator(bob);
        await expectRevert(
          stakePool.removeOperator(bob, {from: bob}),
          'Ownable: caller is not the owner'
        );
      });
    });
  });

  describe('#Stake', async () => {
    before(async () => {
      await ido.mint(alice, web3.utils.toWei(new BN(20000)));
      await ido.approve(stakePool.address, web3.utils.toWei(new BN(20000)), {from: alice});
    });
    describe('##deposit', async () => {
      it('should deposit', async () => {
        await stakePool.deposit(web3.utils.toWei(new BN(5200)), {from: alice});
        await stakePool.stakes(1).then(res => {
          expect(res['amount'].toString()).to.eq('5200000000000000000000');
          expect(res['multiplier'].toString()).to.eq('120');
        });
        const aliceIDOBalance = await ido.balanceOf(alice);
        expect(aliceIDOBalance.toString()).to.eq('14800000000000000000000');
      });
      describe('reverts if', async () => {
        it('stake amount is lower than minimum amount', async () => {
          await expectRevert(
            stakePool.deposit(web3.utils.toWei(new BN(2300)), {from: alice}),
            'StakePool: UNDER_MINIMUM_STAKE_AMOUNT'
          );
        });
      });
    });
    describe('##withdraw', async () => {
      it('should withdraw', async () => {
        await stakePool.withdraw(1, web3.utils.toWei(new BN(2600)), {from: alice});
        await stakePool.stakes(1).then(res => {
          expect(res['amount'].toString()).to.eq('2600000000000000000000');
        });
        await stakePool.withdraw(1, web3.utils.toWei(new BN(2600)), {from: alice});
        await stakePool.stakes(1).then(res => {
          expect(res['amount'].toString()).to.eq('0');
        });
      });
      describe('reverts if', async () => {
        it('withdraw amount is lower than minimum amount', async () => {
          await stakePool.deposit(web3.utils.toWei(new BN(2800)), {from: alice});
          await expectRevert(
            stakePool.withdraw(2, web3.utils.toWei(new BN(2300)), {from: alice}),
            'StakePool: UNDER_MINIMUM_STAKE_AMOUNT'
          );
        });
      });
    });
    describe('##getters', async () => {
      it('getStakeAmount, isHolder, getEligibleStakeAmount', async () => {
        await stakePool.deposit(web3.utils.toWei(new BN(3000)), {from: alice});
        await stakePool.stakerIds(alice, 0).then(res => {
          expect(res.toString()).to.eq('2');
        });
        await stakePool.stakerIds(alice, 1).then(res => {
          expect(res.toString()).to.eq('3');
        });
        await stakePool.getStakeAmount(alice).then(res => {
          expect(res.toString()).to.eq('5800000000000000000000');
        });
        await stakePool.stakes(2).then(res => {
          expect(res['amount'].toString()).to.eq('2800000000000000000000');
          expect(res['multiplier'].toString()).to.eq('120');
          console.log(res['depositedAt'].toString());
        });
        expect(await stakePool.isHolder(alice)).to.eq(true);
        expect(await stakePool.isHolder(bob)).to.eq(false);
      });
    });
  });

  describe('#Reward', async () => {
    describe('##deposit', async () => {
      before(async () => {
        await usdt.mint(alice, web3.utils.toWei(new BN(10000)));
        await usdt.approve(stakePool.address, web3.utils.toWei(new BN(10000)), {from: alice});
      });
      it('should deposit', async () => {
        await stakePool.depositReward(web3.utils.toWei(new BN(4000)), {from: alice});
        await usdt.balanceOf(alice).then(res => {
          expect(res.toString()).to.eq('6000000000000000000000');
        });
        await stakePool.rewardDeposits(0).then(res => {
          expect(res[0]).to.eq(alice);
          expect(res[1].toString()).to.eq('4000000000000000000000');
        });
      });
      describe('reverts if', async () => {
        it('deposit amount is 0', async () => {
          await expectRevert(
            stakePool.depositReward(new BN(0), {from: alice}),
            'StakePool: ZERO_AMOUNT'
          );
        });
        it('non-operator call', async () => {
          await expectRevert(
            stakePool.depositReward(web3.utils.toWei(new BN(4000)), {from: carol}),
            'StakePool: CALLER_NO_OPERATOR_ROLE'
          );
        });
      });
    });
    describe('##distribute', async () => {
      before(async () => {
        // Deposit stake
        await usdt.mint(alice, web3.utils.toWei(new BN(20000)));
        await usdt.approve(stakePool.address, web3.utils.toWei(new BN(20000)), {from: alice});
        await usdt.mint(bob, web3.utils.toWei(new BN(10000)));
        await usdt.approve(stakePool.address, web3.utils.toWei(new BN(10000)), {from: bob});
        await ido.mint(alice, web3.utils.toWei(new BN(10000)));
        await ido.approve(stakePool.address, web3.utils.toWei(new BN(10000)), {from: alice});
        await ido.mint(bob, web3.utils.toWei(new BN(10000)));
        await ido.approve(stakePool.address, web3.utils.toWei(new BN(10000)), {from: bob});
      });
      it('distribute', async () => {
        // After 5 days
        timeTraveler.advanceTime(time.duration.days(5));
        await stakePool.deposit(web3.utils.toWei(new BN(3000)), {from: alice});
        // After 1 day
        timeTraveler.advanceTime(time.duration.days(1));
        await stakePool.deposit(web3.utils.toWei(new BN(6000)), {from: bob});
        // After 10 days
        timeTraveler.advanceTime(time.duration.days(10));
        await stakePool.depositReward(web3.utils.toWei(new BN(4000)), {from: alice});
        // After 1 day
        timeTraveler.advanceTime(time.duration.days(1));
        await stakePool.depositReward(web3.utils.toWei(new BN(4500)), {from: alice});
        // After 15 days (1 month passed)
        timeTraveler.advanceTime(time.duration.days(15));
        await stakePool.distribute({from: bob});
        await stakePool.claimableRewards(alice).then(res => {
          expect(res.toString()).to.eq('2124999999999999997875');
        })
        await stakePool.mDistributes(0).then(res => {
          expect(res[0].toString()).to.eq('2124999999999999997875');
        });

        // After 10 days
        timeTraveler.advanceTime(time.duration.days(10));
        await stakePool.depositReward(web3.utils.toWei(new BN(3000)), {from: alice});
        // After 11 days
        timeTraveler.advanceTime(time.duration.days(11));
        await stakePool.depositReward(web3.utils.toWei(new BN(4500)), {from: alice});
        // After 15 days (2 months passed)
        timeTraveler.advanceTime(time.duration.days(15));
        await stakePool.distribute({from: bob});
        await stakePool.mDistributes(1).then(res => {
          expect(res[0].toString()).to.eq('1874999999999999996250');
        });
        await stakePool.claimableRewards(alice).then(res => {
          expect(res.toString()).to.eq('3239864864864864859750');
        });
        await stakePool.claimableRewards(bob).then(res => {
          expect(res.toString()).to.eq('760135135135135134375');
        });

        expectEvent(
          await stakePool.claimReward(web3.utils.toWei(new BN(700)), {from: alice}),
          'RewardClaimed'
        );
        await stakePool.claimableRewards(alice).then(res => {
          expect(res.toString()).to.eq('2539864864864864859750');
        });
      });
    });
  });
});
