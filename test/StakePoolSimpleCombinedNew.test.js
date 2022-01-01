const { expect } = require('chai');
const { duration } = require('./helpers/time');
const timeTraveler = require('ganache-time-traveler');
const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const StakePool = artifacts.require('contracts/staking/StakePoolSimpleCombinedNew.sol:StakePoolSimpleCombinedNew');
const ERC20 = artifacts.require('ERC20Mock');

contract('::StakePoolSimpleCombinedNew', async accounts => {
  let stakePool, ido, erc20;
  const [alice, bob, carol] = accounts;

  before(async () => {
    ido = await ERC20.new('Idexo Community', 'IDO', {from: alice});
    erc20 = await ERC20.new('USD Tether', 'USDT', {from: alice});
    stakePool = await StakePool.new('Idexo Stake Token', 'IDS', "https://idexo.com/", ido.address, erc20.address, {from: alice});
  });

  describe('# Role', async () => {
    it ('should add operator', async () => {
      await stakePool.addOperator(bob, {from: alice});
      expect(await stakePool.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await stakePool.removeOperator(bob, {from: alice});
      expect(await stakePool.checkOperator(bob)).to.eq(false);
    });
    it('supportsInterface', async () => {
      await stakePool.supportsInterface("0x00").then(res => {
        expect(res).to.eq(false);
      });
    });
    describe('reverts if', async () => {
      it('add operator by non-operator', async () => {
        await expectRevert(
          stakePool.addOperator(bob, {from: bob}),
          'StakePool#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
      it('remove operator by non-operator', async () => {
        await stakePool.addOperator(bob, {from: alice});
        await expectRevert(
          stakePool.removeOperator(bob, {from: bob}),
          'StakePool#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
    });
  });

  describe('# Stake', async () => {
    before(async () => {
      for (const user of [alice, bob, carol]) {
        await ido.mint(user, web3.utils.toWei(new BN(20000)));
        await ido.approve(stakePool.address, web3.utils.toWei(new BN(20000)), {from: user});
        await erc20.mint(user, web3.utils.toWei(new BN(20000)));
        await erc20.approve(stakePool.address, web3.utils.toWei(new BN(20000)), {from: user})
      }
    });

    describe('deposit', async () => {
      it('should deposit', async () => {
        await stakePool.getEligibleStakeAmount(0, {from: alice}).then(res => {
          expect(res.toString()).to.eq('0');
        });
        await stakePool.isHolder(alice).then(res => {
            expect(res.toString()).to.eq('false');
          });
        expectEvent(
          await stakePool.deposit(web3.utils.toWei(new BN(3000)), 0, {from: alice}),
          'Deposited'
        );
        await stakePool.getStakeInfo(1).then(res => {
          expect(res[0].toString()).to.eq('3000000000000000000000');
        });
      });
      it('should deposit reward', async () => {
        expectEvent(
          await stakePool.depositReward(web3.utils.toWei(new BN(3000)), {from: alice}),
          'RewardDeposited'
        );
        await stakePool.getRewardDeposit(0).then(res => {
          expect(res[1].toString()).to.eq('3000000000000000000000');
        });
      });
      it('should add claimable reward', async () => {
        await stakePool.addClaimableReward(1, web3.utils.toWei(new BN(3000)), {from: alice});
        await stakePool.getClaimableReward(1).then(res => {
          expect(res.toString()).to.eq('3000000000000000000000');
        });
      });
      it('should allow claim reward', async () => {
        expectEvent(
          await stakePool.claimReward(1, web3.utils.toWei(new BN(3000)), {from: alice}),
          'RewardClaimed'
        );
      });
    });

    describe('withdraw', async () => {
      it('should withdraw', async () => {
        expectEvent(
          await stakePool.withdraw(1, web3.utils.toWei(new BN(1000)), {from: alice}),
          'StakeAmountDecreased'
        );
        await stakePool.getStakeInfo(1).then(res => {
          expect(res[0].toString()).to.eq('2000000000000000000000');
        });
      });
    });

    describe('transfer', async () => {
        it('should transfer', async () => {
          expectEvent(
            await stakePool.transferFrom(alice, carol, 1, {from: alice}),
            'Transfer'
          );
          await stakePool.getStakeInfo(1).then(res => {
            expect(res[0].toString()).to.eq('2000000000000000000000');
          });
          await stakePool.balanceOf(alice).then(res=>{
            expect(res.toString()).to.eq('0')
          })
          await stakePool.balanceOf(carol).then(res=>{
            expect(res.toString()).to.eq("1");
          })
          await stakePool.getStakeAmount(alice).then(res => {
            expect(res.toString()).to.eq('0');
          });
          await stakePool.getStakeAmount(carol).then(res => {
            expect(res.toString()).to.eq('2000000000000000000000');
          });
        });
      });
  });

  describe('withdraw max', async () => {
    it('should withdraw', async () => {
      expectEvent.notEmitted(
        await stakePool.withdraw(1, web3.utils.toWei(new BN(2000)), {from: carol}),
        'StakeAmountDecreased'
      );
      await stakePool.getStakeAmount(carol).then(res => {
        expect(res.toString()).to.eq('0');
      });
    });
    it('multiple deposits', async () => {
      for (let i = 0; i <= 5; i++) {
        for (const user of [alice, bob, carol]) {
          await stakePool.deposit(web3.utils.toWei(new BN(600)), 0, {from: user})
        }
      }
      for (const user of [bob, alice, carol]) {
        await stakePool.getStakeAmount(user).then(res=>{
          expect(res.toString()).to.not.eq('0')
        })
        let res = await stakePool.getStakeTokenIds(user)
        for (const id of res.toString().split(",")) {
          await stakePool.withdraw(id, web3.utils.toWei(new BN(600)), {from: user})
        }
        await stakePool.getStakeAmount(user).then(res=>{
          expect(res.toString()).to.eq('0')
        })
      }
    });
  });

  describe('deposit with timestamplock', async () => {
    it('should deposit', async () => {
      const number = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(number);
      expectEvent(
        await stakePool.deposit(web3.utils.toWei(new BN(3000)), block.timestamp + duration.days(3), {from: alice}),
        'Deposited'
      );
    });
    it('should not allow withdraw', async () => {
      let res = await stakePool.getStakeTokenIds(alice)
      for (const id of res.toString().split(",")) {
        await expectRevert(
          stakePool.withdraw(id, web3.utils.toWei(new BN(1000)), {from: alice}),
          'StakePool#withdraw: STAKE_STILL_LOCKED_FOR_WITHDRAWAL'
        );
      }
    });
    it('should allow withdraw', async () => {
      timeTraveler.advanceTime(duration.months(1));
      let res = await stakePool.getStakeTokenIds(alice)
      for (const id of res.toString().split(",")) {
        expectEvent(
          await stakePool.withdraw(id, web3.utils.toWei(new BN(1000)), {from: alice}),
          'StakeAmountDecreased'
        );
      }
      timeTraveler.advanceTime(duration.months(-1));
    });
  });
});
