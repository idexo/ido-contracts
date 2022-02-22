function testStakePool(contractName, errorHead, timeIncrease) {
  const { expect } = require('chai');
  const time = require('./helpers/time');
  const timeTraveler = require('ganache-time-traveler');
  const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
  const StakePool = artifacts.require(contractName);
  const ERC20 = artifacts.require('ERC20Mock');
  const IDO = artifacts.require('ERC20Mock');

  contract('::'+ contractName, async accounts => {
    let stakePool;
    let ido;
    let erc20;

    const [alice, bob, carol] = accounts;
    const stakeTokenName = 'Idexo Stake Token';
    const stakeTokenSymbol = 'IDS';
    const erc20Name = 'USD Tether';
    const erc20Symbol = 'USDT';
    const decimals = 18;

    before(async () => {
      ido = await IDO.new('IDO', 'IDO', {from: alice});
      erc20 = await ERC20.new(erc20Name, erc20Symbol, {from: alice});
      stakePool = await StakePool.new(stakeTokenName, stakeTokenSymbol, ido.address, erc20.address, {from: alice});
      await stakePool.addOperator(bob, {from: alice});
    });

    describe('#Role', async () => {
      it ('should add operator', async () => {
        expect(await stakePool.checkOperator(bob)).to.eq(true);
      });
      it('should remove operator', async () => {
        await stakePool.removeOperator(bob, {from: alice});
        expect(await stakePool.checkOperator(bob)).to.eq(false);
      });
      describe('reverts if', async () => {
        it('add operator by non-admin', async () => {
          await expectRevert(
            stakePool.addOperator(bob, {from: bob}),
            errorHead + '#onlyAdmin: CALLER_NO_ADMIN_ROLE'
          );
        });
        it('remove operator by non-admin', async () => {
          await stakePool.addOperator(bob, {from: alice});
          await expectRevert(
            stakePool.removeOperator(bob, {from: bob}),
            errorHead + '#onlyAdmin: CALLER_NO_ADMIN_ROLE'
          );
        });
      });
    });

    describe('#Stake', async () => {
      before(async () => {
        await ido.mint(alice, web3.utils.toWei(new BN(20000)));
        await ido.approve(stakePool.address, web3.utils.toWei(new BN(20000)), {from: alice});
        await ido.mint(carol, web3.utils.toWei(new BN(20000)));
        await ido.approve(stakePool.address, web3.utils.toWei(new BN(20000)), {from: carol});
      });
      describe('##deposit', async () => {
        it('should deposit', async () => {
          await stakePool.deposit(web3.utils.toWei(new BN(5200)), {from: alice});
          await stakePool.getStakeInfo(1).then(res => {
            expect(res[0].toString()).to.eq('5200000000000000000000');
            expect(res[1].toString()).to.eq('120');
          });
          const aliceIDOBalance = await ido.balanceOf(alice);
          expect(aliceIDOBalance.toString()).to.eq('14800000000000000000000');
        });
        describe('reverts if', async () => {
          it('stake amount is lower than minimum amount', async () => {
            await expectRevert(
              stakePool.deposit(web3.utils.toWei(new BN(2300)), {from: alice}),
              errorHead + '#deposit: UNDER_MINIMUM_STAKE_AMOUNT'
            );
          });
        });
      });
      describe('##withdraw', async () => {
        it('should withdraw', async () => {
          await stakePool.withdraw(1, web3.utils.toWei(new BN(2600)), {from: alice});
          await stakePool.getStakeInfo(1).then(res => {
            expect(res[0].toString()).to.eq('2600000000000000000000');
          });
          await stakePool.withdraw(1, web3.utils.toWei(new BN(2600)), {from: alice});
          await expectRevert(
            stakePool.getStakeInfo(1),
            'StakeToken#getStakeInfo: STAKE_NOT_FOUND'
          );
        });
        describe('reverts if', async () => {
          it('withdraw amount is lower than minimum amount', async () => {
            await stakePool.deposit(web3.utils.toWei(new BN(2800)), {from: alice});
            await expectRevert(
              stakePool.withdraw(2, web3.utils.toWei(new BN(2300)), {from: alice}),
              errorHead + '#withdraw: UNDER_MINIMUM_STAKE_AMOUNT'
            );
          });
        });
      });
      describe("##burn", async () => {
          it("should stake and withdraw/burn", async () => {
            await stakePool.deposit(web3.utils.toWei(new BN(5000)), { from: carol })
            await stakePool.deposit(web3.utils.toWei(new BN(5000)), { from: carol })
              await stakePool.withdraw(3, web3.utils.toWei(new BN(5000)), { from: carol })
              await stakePool.withdraw(4, web3.utils.toWei(new BN(5000)), { from: carol })
              await expectRevert(stakePool.getStakeInfo(3), "StakeToken#getStakeInfo: STAKE_NOT_FOUND")
          })
      })
      describe('##getters', async () => {
        it('supportsInterface', async () => {
          await stakePool.supportsInterface("0x00").then(res => {
            expect(res).to.eq(false);
          });
        });
        it('getStakeTokenIds, getStakeAmount, isHolder, getEligibleStakeAmount', async () => {
          await stakePool.deposit(web3.utils.toWei(new BN(3000)), {from: alice});
          await stakePool.getStakeTokenIds(alice).then(res => {
            expect(res.length).to.eq(2);
            expect(res[0].toString()).to.eq('2');
            expect(res[1].toString()).to.eq('5');
          });
          await stakePool.getStakeAmount(alice).then(res => {
            expect(res.toString()).to.eq('5800000000000000000000');
          });
          await stakePool.getStakeInfo(2).then(res => {
            expect(res[0].toString()).to.eq('2800000000000000000000');
            expect(res[1].toString()).to.eq('120');
            console.log(res[2].toString());
          });
          expect(await stakePool.isHolder(alice)).to.eq(true);
          expect(await stakePool.isHolder(bob)).to.eq(false);
          await stakePool.getEligibleStakeAmount(0).then((res) => {
              expect(res.toString()).to.eq("0")
          })
          // let elegibleStake = await stakePool.getEligibleStakeAmount(0, {from: alice})
          // console.log("Elegible Stake Amount:",elegibleStake.toString())
        });
        describe('reverts if', async () => {
          it('elegible stake amount date is invalid', async () => {
            const futureTime = Math.floor(Date.now() / 1000) + time.duration.days(300);
            await expectRevert(
              stakePool.getEligibleStakeAmount(futureTime, {from: alice}),
              'StakeToken#getEligibleStakeAmount: NO_PAST_DATE'
            );
          });
        });
      });
    });

    describe('#Reward', async () => {
      describe('##deposit', async () => {
        before(async () => {
          await erc20.mint(alice, web3.utils.toWei(new BN(10001)));
          await erc20.approve(stakePool.address, web3.utils.toWei(new BN(10000)), {from: alice});
          await erc20.burn(alice, web3.utils.toWei(new BN(1)));
        });
        it('should deposit', async () => {
          await stakePool.depositReward(web3.utils.toWei(new BN(4000)), {from: alice});
          await erc20.balanceOf(alice).then(res => {
            expect(res.toString()).to.eq('6000000000000000000000');
          });
          await stakePool.getRewardDeposit(0).then(res => {
            expect(res[0]).to.eq(alice);
            expect(res[1].toString()).to.eq('4000000000000000000000');
          });
        });
        it('sweep', async () => {
          expectEvent(
            await stakePool.sweep(ido.address, alice, 1, {from: alice}),
            'Swept'
          );
        });
        describe('reverts if', async () => {
          it('deposit amount is 0', async () => {
            await expectRevert(
              stakePool.depositReward(new BN(0), {from: alice}),
              errorHead + '#depositReward: ZERO_AMOUNT'
            );
          });
          it('non-operator call', async () => {
            await expectRevert(
              stakePool.depositReward(web3.utils.toWei(new BN(4000)), {from: carol}),
              errorHead + '#onlyOperator: CALLER_NO_OPERATOR_ROLE'
            );
          });
          it('non-operator call sweep', async () => {
            await expectRevert(
              stakePool.sweep(ido.address, alice, 1, {from: carol}),
              errorHead + '#onlyOperator: CALLER_NO_OPERATOR_ROLE'
            );
          });
        });
      });
      describe('##distribute', async () => {
        before(async () => {
          // Deposit stake
          await erc20.mint(alice, web3.utils.toWei(new BN(20000)));
          await erc20.approve(stakePool.address, web3.utils.toWei(new BN(20000)), {from: alice});
          await erc20.mint(bob, web3.utils.toWei(new BN(10000)));
          await erc20.approve(stakePool.address, web3.utils.toWei(new BN(10000)), {from: bob});
          await ido.mint(alice, web3.utils.toWei(new BN(10000)));
          await ido.approve(stakePool.address, web3.utils.toWei(new BN(10000)), {from: alice});
          await ido.mint(bob, web3.utils.toWei(new BN(10000)));
          await ido.approve(stakePool.address, web3.utils.toWei(new BN(10000)), {from: bob});
        });
        describe('reverts if', async () => {
          it('distribute non-operator', async () => {
            await expectRevert(
              stakePool.distribute({from: carol}),
              errorHead + '#onlyOperator: CALLER_NO_OPERATOR_ROLE'
            );
          });
          it('claim not owner', async () => {
            await expectRevert(
              stakePool.claimReward(100, {from: carol}),
              errorHead + '#claimReward: CALLER_NO_TOKEN_OWNER'
            );
          });
          it('claim without funds', async () => {
            await expectRevert(
              stakePool.claimReward(web3.utils.toWei(new BN(1000000)), {from: bob}),
              errorHead + '#claimReward: INSUFFICIENT_FUNDS'
            );
          });
        });
        it('distribute', async () => {
          // After 5 days
          timeTraveler.advanceTime(time.duration.days(timeIncrease[0]));
          await stakePool.deposit(web3.utils.toWei(new BN(3000)), {from: alice});
          // After 1 day
          timeTraveler.advanceTime(time.duration.days(timeIncrease[1]));
          await stakePool.deposit(web3.utils.toWei(new BN(6000)), {from: bob});
          // After 10 days
          timeTraveler.advanceTime(time.duration.days(timeIncrease[2]));
          await stakePool.depositReward(web3.utils.toWei(new BN(4000)), {from: alice});
          // After 1 day
          timeTraveler.advanceTime(time.duration.days(timeIncrease[3]));
          await stakePool.depositReward(web3.utils.toWei(new BN(4500)), {from: alice});
          // After 15 days (1 month passed)
          timeTraveler.advanceTime(time.duration.days(timeIncrease[4]));
          await stakePool.distribute({from: bob});
          await stakePool.claimableRewards(alice).then(res => {
            expect(res.toString()).to.eq('2124999999999999997875');
          })
          await stakePool.mDistributes(0).then(res => {
            expect(res[0].toString()).to.eq('2124999999999999997875');
          });

          // After 10 days
          timeTraveler.advanceTime(time.duration.days(timeIncrease[5]));
          await stakePool.depositReward(web3.utils.toWei(new BN(3000)), {from: alice});
          // After 11 days
          timeTraveler.advanceTime(time.duration.days(timeIncrease[6]));
          await stakePool.depositReward(web3.utils.toWei(new BN(4500)), {from: alice});
          // After 15 days (2 months passed)
          timeTraveler.advanceTime(time.duration.days(timeIncrease[7]));
          await stakePool.distribute({from: bob});
          if (timeIncrease[7] > 0) {
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
          }
        });
        it('distribute after a year', async () => {
          timeTraveler.advanceTime(time.duration.months(15));
          await stakePool.distribute({from: bob}).then(res => {
            expect(res).to.not.null;
          });
        });

        it('distribute after two years', async () => {
          timeTraveler.advanceTime(time.duration.months(15));
          await stakePool.distribute({from: bob}).then(res => {
            expect(res).to.not.null;
          });
        });
        after(async () => {
          for (let i = 0; i < timeIncrease.length; i++) {
            timeTraveler.advanceTime(time.duration.days(timeIncrease[i] * -1));
          }
          timeTraveler.advanceTime(time.duration.months(-30));
        });
      });
    });

    describe('#Multiplier', function () {
      // this.timeout(120000)
      before(async () => {
        await ido.mint(alice, web3.utils.toWei(new BN(20000000)));
        await ido.approve(stakePool.address, web3.utils.toWei(new BN(20000000)), {from: alice});
      });
      it('getStakeInfo', async () => {
        for (let i = 0; i < 301; i++) {
            await stakePool.deposit(web3.utils.toWei(new BN(3000)), {from: alice});
        }
        await stakePool.getStakeInfo(299).then(res => {
          expect(res[1].toString()).to.eq('120');
        });
        await stakePool.getStakeInfo(301).then(res => {
          expect(res[1].toString()).to.eq('110');
        });
        // await stakePool.getStakeInfo(4000).then(res => {
        //   expect(res[1].toString()).to.eq('100');
        // });
      });
    });
  });
}

module.exports = { testStakePool };