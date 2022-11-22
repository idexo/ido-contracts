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
    const DOMAIN = "https://idexo.com/"

    before(async () => {
      ido = await IDO.new('IDO', 'IDO', {from: alice});
      erc20 = await ERC20.new(erc20Name, erc20Symbol, {from: alice});
      stakePool = await StakePool.new(stakeTokenName, stakeTokenSymbol, DOMAIN, ido.address, erc20.address, {from: alice});
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
        await ido.mint(alice, web3.utils.toWei(new BN(200000)));
        await ido.approve(stakePool.address, web3.utils.toWei(new BN(200000)), {from: alice});
        await ido.mint(bob, web3.utils.toWei(new BN(200000)));
        await ido.approve(stakePool.address, web3.utils.toWei(new BN(200000)), {from: bob});
        await ido.mint(carol, web3.utils.toWei(new BN(200000)));
        await ido.approve(stakePool.address, web3.utils.toWei(new BN(200000)), {from: carol});
      });
      describe('##deposit', async () => {
        it('should deposit', async () => {
          await stakePool.deposit(web3.utils.toWei(new BN(5200)), {from: alice});
          await stakePool.getStakeInfo(1).then(res => {
            expect(res[0].toString()).to.eq('5200000000000000000000');
            expect(res[1].toString()).to.eq('120');
          });
          const aliceIDOBalance = await ido.balanceOf(alice);
          expect(aliceIDOBalance.toString()).to.eq('194800000000000000000000');
        });
        it('should add claimable reward', async () => {
            await stakePool.addClaimableReward(1, web3.utils.toWei(new BN(300)), {from: alice});
            await stakePool.getClaimableReward(1).then(res => {
              expect(res.toString()).to.eq('300000000000000000000');
            });
          });
          it('should allow claim reward', async () => {
            expectEvent( await stakePool.claimReward(1, 0, {from: alice}), 'RewardClaimed');
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
    });

    describe("multiple deposits and distribute rewards", async () => {
        it("multiple deposits", async () => {
            for (const user of [alice, bob, carol]) {
                await stakePool.deposit(web3.utils.toWei(new BN(5000)), { from: user })
            }
            for (const user of [bob, alice, carol]) {
                await stakePool.getStakeAmount(user).then((res) => {
                    expect(res.toString()).to.not.eq("0")
                })
            }
        })
        it("should new deposit rewards", async () => {
            expectEvent(await stakePool.depositReward(web3.utils.toWei(new BN(6000)), { from: alice }), "RewardDeposited")
            await stakePool.getRewardDeposit(1).then((res) => {
                expect(res[1].toString()).to.eq("6000000000000000000000")
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

        // it("should change tokenURI", async () => {
        //     await stakePool.setTokenURI(1, "test", { from: alice })
        //     await stakePool.tokenURI(1).then((res) => {
        //         expect(res.toString()).to.eq(DOMAIN + "test")
        //     })
        // })
        it("should change baseURI", async () => {
            await stakePool.setBaseURI("http://newdomain/", { from: alice })
            await stakePool.baseURI().then((res) => {
                expect(res.toString()).to.eq("http://newdomain/")
            })
        })
        describe("reverts if", async () => {
            it("change tokenURI by NO-OPERATOR", async () => {
                await expectRevert(stakePool.setTokenURI(1, "test", { from: bob }), "Ownable: caller is not the owner")
            })
        })
    })
  });
}

module.exports = { testStakePool };