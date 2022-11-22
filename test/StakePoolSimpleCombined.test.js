const { expect } = require('chai');
const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const StakePool = artifacts.require('contracts/staking/StakePoolSimpleCombined.sol:StakePoolSimpleCombined');
const ERC20 = artifacts.require('ERC20Mock');

contract('::StakePoolSimpleCombined', async accounts => {
  let stakePool, ido, erc20;
  const [alice, bob, carol] = accounts;

  before(async () => {
    ido = await ERC20.new('Idexo Community', 'IDO', {from: alice});
    erc20 = await ERC20.new('USD Tether', 'USDT', {from: alice});
    stakePool = await StakePool.new('Idexo Stake Token', 'IDS', '', ido.address, erc20.address, {from: alice});
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
      await ido.mint(alice, web3.utils.toWei(new BN(100000)));
      await ido.approve(stakePool.address, web3.utils.toWei(new BN(100000)), {from: alice});
      await ido.mint(bob, web3.utils.toWei(new BN(100000)));
      await ido.approve(stakePool.address, web3.utils.toWei(new BN(100000)), {from: bob});
      await ido.mint(carol, web3.utils.toWei(new BN(100000)));
      await ido.approve(stakePool.address, web3.utils.toWei(new BN(100000)), {from: carol});
      await erc20.mint(alice, web3.utils.toWei(new BN(100000)));
      await erc20.approve(stakePool.address, web3.utils.toWei(new BN(100000)), {from: alice})
    });

    describe('deposit', async () => {
      it('should deposit', async () => {
        expectEvent(
          await stakePool.deposit(web3.utils.toWei(new BN(3000)), {from: alice}),
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
        });
      });
  });

  describe("multiple deposits and distribute rewards", async () => {
      it("multiple deposits", async () => {
          for (let i = 0; i <= 1; i++) {
              for (const user of [alice, bob, carol]) {
                  await stakePool.deposit(web3.utils.toWei(new BN(5000)), { from: user })
              }
          }
          for (const user of [bob, alice, carol]) {
              await stakePool.getStakeAmount(user).then((res) => {
                  expect(res.toString()).to.not.eq("0")
              })
          }
      })
      it("should new deposit rewards", async () => {
          expectEvent(await stakePool.depositReward(web3.utils.toWei(new BN(60000)), { from: alice }), "RewardDeposited")
          await stakePool.getRewardDeposit(1).then((res) => {
              expect(res[1].toString()).to.eq("60000000000000000000000")
          })
      })

      it("should add claimable rewards", async () => {
          const amountForRewards = web3.utils.toWei(new BN(5000))

          await stakePool.addClaimableRewards(
              [21, 22, 23, 24, 25, 26],
              [amountForRewards, amountForRewards, amountForRewards, amountForRewards, amountForRewards, amountForRewards],
              {
                  from: alice
              }
          )
          await stakePool.getClaimableReward(21).then((res) => {
              expect(res.toString()).to.eq("5000000000000000000000")
          })
      })
  })

   describe("# Sweep", async () => {
       it("should sweep funds to another account", async () => {
           let balance = await erc20.balanceOf(stakePool.address)
           balance = await erc20.balanceOf(stakePool.address)
           await stakePool.sweep(erc20.address, bob, web3.utils.toWei(new BN(3000)), { from: bob })
       })
   })

});
