const { expect } = require("chai")
const { duration } = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const { network } = require("hardhat")
const StakePool = artifacts.require("contracts/staking/StakePoolMultRewardsTimeLimitedV1.sol:StakePoolMultRewardsTimeLimitedV1")
const ERC20 = artifacts.require("ERC20Mock")

contract("::StakePoolMultRewardsTimeLimited", async (accounts) => {
    let stakePool, ido, usdt, usdc
    const [owner, alice, bob, carol, darren] = accounts
    const DOMAIN = "https://idexo.com/"

    before(async () => {
        const minPoolStakeAmount = web3.utils.toWei(new BN(10000))
        ido = await ERC20.new("Idexo Community", "IDO", { from: owner })
        usdt = await ERC20.new("USD Tether", "USDT", { from: owner })
        usdc = await ERC20.new("USDC Coin", "USDC", { from: owner })
        stakePool = await StakePool.new("Idexo Stake Token", "IDS", DOMAIN, 1, minPoolStakeAmount, ido.address, usdt.address, { from: owner })
    })

    describe("# Role", async () => {
        it("should add operator", async () => {
            await stakePool.addOperator(alice, { from: owner })
            expect(await stakePool.checkOperator(alice)).to.eq(true)
        })
        it("should remove operator", async () => {
            await stakePool.removeOperator(alice, { from: owner })
            expect(await stakePool.checkOperator(alice)).to.eq(false)
        })
        it("supportsInterface", async () => {
            await stakePool.supportsInterface("0x00").then((res) => {
                expect(res).to.eq(false)
            })
        })
        describe("reverts if", async () => {
            it("add operator by NO-OWNER", async () => {
                await expectRevert(stakePool.addOperator(bob, { from: alice }), "Ownable: CALLER_NO_OWNER")
            })
            it("remove operator by NO-OWNER", async () => {
                await stakePool.addOperator(bob, { from: owner })
                await expectRevert(stakePool.removeOperator(bob, { from: alice }), "Ownable: CALLER_NO_OWNER")
            })
        })
    })

    describe("# Reward Tokens", async () => {
        it("should add USDC token reward", async () => {
            await stakePool.addRewardToken(usdc.address, { from: bob })
        })
        describe("reverts if", async () => {
            it("add reward token by NO-OPERATOR", async () => {
                await expectRevert(stakePool.addRewardToken(usdc.address, { from: alice }), "Operatorable: CALLER_NO_OPERATOR_ROLE")
            })
        })
    })

    describe("# Get Contract info", async () => {
        it("should get timeLimitInDays", async () => {
            await stakePool.timeLimitInDays().then((res) => {
                expect(res.toString()).to.eq("1")
            })
        })
        it("should get minPoolStakeAmount", async () => {
            await stakePool.minPoolStakeAmount().then((res) => {
                expect(res.toString()).to.eq(web3.utils.toWei(new BN(10000)).toString())
            })
        })

        it("should get timeLimit", async () => {
            await stakePool.timeLimit().then((res) => {
                expect(res.toString()).to.eq("0")
            })
        })
    })

    describe("# Staking", async () => {
        before(async () => {
            for (const user of [alice, bob, carol, darren]) {
                await ido.mint(user, web3.utils.toWei(new BN(20000)))
                await ido.approve(stakePool.address, web3.utils.toWei(new BN(20000)), { from: user })
            }
        })

        describe("staking", async () => {
            it("check getMultiplier", async () => {
                await stakePool.getMultiplier(1).then((res) => {
                    expect(res.toString()).to.eq("120")
                })
                await stakePool.getMultiplier(301).then((res) => {
                    expect(res.toString()).to.eq("110")
                })
                await stakePool.getMultiplier(4001).then((res) => {
                    expect(res.toString()).to.eq("100")
                })
            })
            it("should stake 1", async () => {
                await stakePool.getEligibleStakeAmount(0, { from: alice }).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                await stakePool.isHolder(alice).then((res) => {
                    expect(res.toString()).to.eq("false")
                })
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(500)), 0, { from: alice }), "Deposited")
                await ido.balanceOf(stakePool.address).then((res) => {
                    expect(res.toString()).to.eq("500000000000000000000")
                })
                await stakePool.getStakeInfo(1).then((res) => {
                    expect(res[0].toString()).to.eq("500000000000000000000")
                })
            })
            it("should stake 2", async () => {
                await stakePool.getEligibleStakeAmount(0, { from: carol }).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                let number = await ethers.provider.getBlockNumber()
                let block = await ethers.provider.getBlock(number)
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }), "Deposited")
                await stakePool.getStakeInfo(2).then((res) => {
                    expect(res[0].toString()).to.eq("5000000000000000000000")
                })
                await stakePool.isHolder(carol).then((res) => {
                    expect(res.toString()).to.eq("true")
                })
                await timeTraveler.advanceTime(duration.months(10))
                await stakePool.getEligibleStakeAmount(block.timestamp, { from: carol }).then((res) => {
                    expect(res.toString()).to.not.eq("0")
                })
                await timeTraveler.advanceTime(duration.months(-10))
            })
            it("should stake 3", async () => {
                await stakePool.getEligibleStakeAmount(0, { from: carol }).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                let number = await ethers.provider.getBlockNumber()
                let block = await ethers.provider.getBlock(number)
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }), "Deposited")
                await stakePool.getStakeInfo(3).then((res) => {
                    expect(res[0].toString()).to.eq("5000000000000000000000")
                })
                await stakePool.isHolder(carol).then((res) => {
                    expect(res.toString()).to.eq("true")
                })
                await timeTraveler.advanceTime(duration.months(10))
                await stakePool.getEligibleStakeAmount(block.timestamp, { from: carol }).then((res) => {
                    expect(res.toString()).to.not.eq("0")
                })
                await timeTraveler.advanceTime(duration.months(-10))
            })

            describe("should withdraw before and after pool closed", async () => {
                it("should withdraw stake 3 before", async () => {
                    expectEvent(await stakePool.withdraw(3, web3.utils.toWei(new BN(5000)), { from: carol }), "Withdrawn")
                    await stakePool.isHolder(carol).then((res) => {
                        expect(res.toString()).to.eq("true")
                    })
                    await stakePool.timeLimit().then((res) => {
                        expect(res.toString()).to.eq("0")
                    })
                })
                it("should stake 4", async () => {
                    await stakePool.deposit(web3.utils.toWei(new BN(600)), 0, { from: darren })
                })
                it("should withdraw stake 5 after pool closed", async () => {
                    expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }), "Deposited")
                    await timeTraveler.advanceTimeAndBlock(duration.days(1))
                    expectEvent(await stakePool.withdraw(5, web3.utils.toWei(new BN(5000)), { from: carol }), "Withdrawn")
                    await stakePool.timeLimit().then((res) => {
                        expect(res.toString()).to.not.eq("0")
                    })
                    await timeTraveler.advanceTimeAndBlock(duration.days(-1))
                })
            })

            describe("should revert stake after pool closed", async () => {
                it("should revert stake 5 if DEPOSIT_TIME_CLOSED", async () => {
                    await ido.balanceOf(stakePool.address).then((res) => {
                        expect(res.toString()).to.eq("6100000000000000000000")
                    })
                    await timeTraveler.advanceTimeAndBlock(duration.days(1))
                    await expectRevert(
                        stakePool.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }),
                        "StakePool#_deposit: DEPOSIT_TIME_CLOSED"
                    )
                    await timeTraveler.advanceTimeAndBlock(duration.days(-1))
                })
            })
        })
    })

    describe("# URI", async () => {
        it("should change tokenURI", async () => {
            await stakePool.setTokenURI(1, "test", { from: owner }),
                await stakePool.tokenURI(1).then((res) => {
                    expect(res.toString()).to.eq(DOMAIN + "test")
                })
        })
        it("should change baseURI", async () => {
            await stakePool.setBaseURI("http://newdomain/", { from: owner }),
                await stakePool.baseURI().then((res) => {
                    expect(res.toString()).to.eq("http://newdomain/")
                })
        })
        describe("reverts if", async () => {
            it("change tokenURI by NO-OPERATOR", async () => {
                await expectRevert(stakePool.setTokenURI(1, "test", { from: alice }), "Ownable: CALLER_NO_OWNER")
            })
        })
    })

    describe("# Rewards", async () => {
        before(async () => {
            for (const user of [owner, alice, bob]) {
                await usdt.mint(user, web3.utils.toWei(new BN(100000)), { from: owner })
                await usdt.approve(stakePool.address, web3.utils.toWei(new BN(100000)), { from: user })
                await usdc.mint(user, web3.utils.toWei(new BN(100000)), { from: owner })
                await usdc.approve(stakePool.address, web3.utils.toWei(new BN(100000)), { from: user })
            }
        })
        describe("deposit rewards", async () => {
            it("should deposit USDT reward", async () => {
                expectEvent(await stakePool.depositReward(usdt.address, web3.utils.toWei(new BN(50000)), { from: owner }), "RewardDeposited")
                await stakePool.getRewardDeposit(usdt.address, 0).then((res) => {
                    expect(res[1].toString()).to.eq("50000000000000000000000")
                })
            })
            it("should deposit USDC reward", async () => {
                expectEvent(await stakePool.depositReward(usdc.address, web3.utils.toWei(new BN(20000)), { from: bob }), "RewardDeposited")
                await stakePool.getRewardDeposit(usdc.address, 0).then((res) => {
                    expect(res[1].toString()).to.eq("20000000000000000000000")
                })
            })
        })
        describe("claimable reward", async () => {
            it("should add claimable USDT reward to 1", async () => {
                await stakePool.addClaimableReward(usdt.address, 1, web3.utils.toWei(new BN(5000)), { from: owner })
                await stakePool.getClaimableReward(usdt.address, 1).then((res) => {
                    expect(res.toString()).to.eq("5000000000000000000000")
                })
            })
            it("should add claimable USDC reward to 1", async () => {
                await stakePool.addClaimableReward(usdc.address, 1, web3.utils.toWei(new BN(5000)), { from: owner })
                await stakePool.getClaimableReward(usdc.address, 1).then((res) => {
                    expect(res.toString()).to.eq("5000000000000000000000")
                })
            })
        })
        describe("claimable rewards", async () => {
            const tokenIds = [1, 2]
            const rewardsUSDT = [web3.utils.toWei(new BN(22500)), web3.utils.toWei(new BN(22500))]
            const rewardsUSDC = [web3.utils.toWei(new BN(7500)), web3.utils.toWei(new BN(7500))]
            it("should add claimable USDT rewards to 1 and 2", async () => {
                await stakePool.addClaimableRewards(usdt.address, tokenIds, rewardsUSDT, {
                    from: owner
                })
                await stakePool.getClaimableReward(usdt.address, 1).then((res) => {
                    expect(res.toString()).to.eq("27500000000000000000000")
                })
                await stakePool.getClaimableReward(usdt.address, 2).then((res) => {
                    expect(res.toString()).to.eq("22500000000000000000000")
                })
            })
            it("should add claimable USDC rewards to 1 and 2", async () => {
                await stakePool.addClaimableRewards(usdc.address, tokenIds, rewardsUSDC, {
                    from: owner
                })
                await stakePool.getClaimableReward(usdc.address, 1).then((res) => {
                    expect(res.toString()).to.eq("12500000000000000000000")
                })
                await stakePool.getClaimableReward(usdc.address, 2).then((res) => {
                    expect(res.toString()).to.eq("7500000000000000000000")
                })
            })
        })
        describe("claim rewards", async () => {
            it("should allow claim full USDT reward to 1", async () => {
                expectEvent(await stakePool.claimReward(usdt.address, 1, web3.utils.toWei(new BN(27500)), { from: alice }), "RewardClaimed")
                await stakePool.getClaimableReward(usdt.address, 1).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
            })
            it("should allow claim full USDT reward to 2", async () => {
                expectEvent(await stakePool.claimReward(usdt.address, 2, web3.utils.toWei(new BN(22500)), { from: carol }), "RewardClaimed")
                await stakePool.getClaimableReward(usdt.address, 2).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
            })
            it("should allow claim full USDC reward to 1", async () => {
                expectEvent(await stakePool.claimReward(usdc.address, 1, web3.utils.toWei(new BN(12500)), { from: alice }), "RewardClaimed")
                await stakePool.getClaimableReward(usdc.address, 1).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
            })
            it("should allow claim partial USDC reward to 2", async () => {
                expectEvent(await stakePool.claimReward(usdc.address, 2, web3.utils.toWei(new BN(5000)), { from: carol }), "RewardClaimed")
                await stakePool.getClaimableReward(usdc.address, 2).then((res) => {
                    expect(res.toString()).to.eq("2500000000000000000000")
                })
            })
        })
    })

    describe("# Transfer", async () => {
        describe("transfers", async () => {
            it("should transfer", async () => {
                await stakePool.currentSupply().then((res) => {
                    expect(res.toString()).to.eq("3")
                })
                expectEvent(await stakePool.transferFrom(alice, carol, 1, { from: alice }), "Transfer")
                await stakePool.getStakeInfo(1).then((res) => {
                    expect(res[0].toString()).to.eq("500000000000000000000")
                })
                await stakePool.balanceOf(alice).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                await stakePool.balanceOf(carol).then((res) => {
                    expect(res.toString()).to.eq("2")
                })
                await stakePool.getStakeAmount(alice).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                await stakePool.getStakeAmount(carol).then((res) => {
                    expect(res.toString()).to.eq("5500000000000000000000")
                })
            })
        })
    })

    // describe("# Withdraw", async () => {
    //     describe("partial withdraw", async () => {
    //         it("should withdraw", async () => {
    //             expectEvent(await stakePool.withdraw(1, web3.utils.toWei(new BN(1000)), { from: carol }), "StakeAmountDecreased")
    //             await stakePool.getStakeInfo(1).then((res) => {
    //                 expect(res[0].toString()).to.eq("2000000000000000000000")
    //             })
    //         })
    //     })

    //     describe("withdraw max", async () => {
    //         it("should withdraw", async () => {
    //             await stakePool.currentSupply().then((res) => {
    //                 expect(res.toString()).to.eq("3")
    //             })
    //             expectEvent.notEmitted(await stakePool.withdraw(1, web3.utils.toWei(new BN(2000)), { from: carol }), "StakeAmountDecreased")
    //             await stakePool.getStakeAmount(carol).then((res) => {
    //                 expect(res.toString()).to.eq("5000000000000000000000")
    //             })
    //             await stakePool.currentSupply().then((res) => {
    //                 expect(res.toString()).to.eq("2")
    //             })
    //             expectEvent.notEmitted(await stakePool.withdraw(2, web3.utils.toWei(new BN(5000)), { from: carol }), "StakeAmountDecreased")
    //             await stakePool.getStakeAmount(carol).then((res) => {
    //                 expect(res.toString()).to.eq("0")
    //             })
    //             await stakePool.currentSupply().then((res) => {
    //                 expect(res.toString()).to.eq("1")
    //             })
    //         })
    //     })

    //     describe("multiples deposits and withdraws", async () => {
    //         it("multiple deposits", async () => {
    //             for (let i = 0; i <= 5; i++) {
    //                 for (const user of [alice, carol, darren]) {
    //                     await stakePool.deposit(web3.utils.toWei(new BN(600)), 0, { from: user })
    //                 }
    //             }

    //             await stakePool.currentSupply().then((res) => {
    //                 expect(res.toString()).to.eq("19")
    //             })
    //         })
    //         it("multiple withdraw", async () => {
    //             for (const user of [darren, alice, carol]) {
    //                 await stakePool.getStakeAmount(user).then((res) => {
    //                     expect(res.toString()).to.not.eq("0")
    //                 })
    //                 let res = await stakePool.getStakeTokenIds(user)
    //                 for (const id of res.toString().split(",")) {
    //                     await stakePool.withdraw(id, web3.utils.toWei(new BN(600)), { from: user })
    //                 }
    //                 await stakePool.getStakeAmount(user).then((res) => {
    //                     expect(res.toString()).to.eq("0")
    //                 })
    //             }

    //             await stakePool.currentSupply().then((res) => {
    //                 expect(res.toString()).to.eq("0")
    //             })
    //         })
    //     })

    //     describe("reverts if", async () => {
    //         it("tokenId not exist", async () => {
    //             await expectRevert(
    //                 stakePool.withdraw(3, web3.utils.toWei(new BN(1000)), { from: alice }),
    //                 "ERC721: owner query for nonexistent token"
    //             )
    //         })
    //     })
    // })

    // describe("# Locked Deposits", async () => {
    //     describe("deposit with timestamplock", async () => {
    //         it("should deposit", async () => {
    //             const number = await ethers.provider.getBlockNumber()
    //             const block = await ethers.provider.getBlock(number)
    //             expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(3000)), block.timestamp + duration.days(3), { from: alice }), "Deposited")
    //         })
    //         it("should not allow withdraw", async () => {
    //             let res = await stakePool.getStakeTokenIds(alice)
    //             for (const id of res.toString().split(",")) {
    //                 await expectRevert(
    //                     stakePool.withdraw(id, web3.utils.toWei(new BN(1000)), { from: alice }),
    //                     "StakePool#withdraw: STAKE_STILL_LOCKED_FOR_WITHDRAWAL"
    //                 )
    //             }
    //         })
    //         it("should allow withdraw", async () => {
    //             timeTraveler.advanceTime(duration.months(1))
    //             let res = await stakePool.getStakeTokenIds(alice)
    //             for (const id of res.toString().split(",")) {
    //                 expectEvent(await stakePool.withdraw(id, web3.utils.toWei(new BN(1000)), { from: alice }), "StakeAmountDecreased")
    //             }
    //             timeTraveler.advanceTime(duration.months(-1))
    //         })
    //     })
    // })

    // describe("# Sweep", async () => {
    //     it("should sweep funds to another account", async () => {
    //         let balance = await usdt.balanceOf(stakePool.address)
    //         balance = await usdc.balanceOf(stakePool.address)
    //         await stakePool.sweep(usdc.address, darren, web3.utils.toWei(new BN(2500)), { from: bob })
    //         balance = await usdc.balanceOf(stakePool.address)
    //     })
    // })

    // describe("# Stake, Deposit Rewards, Add Rewards, Withdraw with pending Claim Rewards", async () => {
    //     it("stake", async () => {
    //         await stakePool.getEligibleStakeAmount(0, { from: darren }).then((res) => {
    //             expect(res.toString()).to.eq("0")
    //         })
    //         await stakePool.isHolder(darren).then((res) => {
    //             expect(res.toString()).to.eq("false")
    //         })
    //         expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(3000)), 0, { from: darren }), "Deposited")

    //         let res = await stakePool.getStakeTokenIds(darren)
    //         await stakePool.getStakeInfo(23).then((res) => {
    //             expect(res[0].toString()).to.eq("3000000000000000000000")
    //         })
    //     })

    //     it("should deposit USDT reward", async () => {
    //         expectEvent(await stakePool.depositReward(usdt.address, web3.utils.toWei(new BN(10000)), { from: owner }), "RewardDeposited")
    //         await stakePool.getRewardDeposit(usdt.address, 1).then((res) => {
    //             expect(res[1].toString()).to.eq("10000000000000000000000")
    //         })
    //     })

    //     it("should deposit USDC reward", async () => {
    //         expectEvent(await stakePool.depositReward(usdc.address, web3.utils.toWei(new BN(10000)), { from: bob }), "RewardDeposited")
    //         await stakePool.getRewardDeposit(usdc.address, 1).then((res) => {
    //             expect(res[1].toString()).to.eq("10000000000000000000000")
    //         })
    //     })

    //     it("should add claimable USDT reward", async () => {
    //         await stakePool.addClaimableReward(usdt.address, 23, web3.utils.toWei(new BN(10000)), { from: owner })
    //         await stakePool.getClaimableReward(usdt.address, 23).then((res) => {
    //             expect(res.toString()).to.eq("10000000000000000000000")
    //         })
    //     })

    //     it("should add claimable USDC reward", async () => {
    //         await stakePool.addClaimableReward(usdc.address, 23, web3.utils.toWei(new BN(10000)), { from: owner })
    //         await stakePool.getClaimableReward(usdc.address, 23).then((res) => {
    //             expect(res.toString()).to.eq("10000000000000000000000")
    //         })
    //     })

    //     it("full withdraw", async () => {
    //         expectEvent.notEmitted(await stakePool.withdraw(23, web3.utils.toWei(new BN(3000)), { from: darren }), "StakeAmountDecreased")
    //         await stakePool.getStakeAmount(darren).then((res) => {
    //             expect(res.toString()).to.eq("0")
    //         })
    //         await stakePool.currentSupply().then((res) => {
    //             expect(res.toString()).to.eq("1")
    //         })
    //     })

    //     describe("reverts if withdraw before claim", async () => {
    //         it("should not allow claim USDT reward", async () => {
    //             await expectRevert(
    //                 stakePool.claimReward(usdt.address, 23, web3.utils.toWei(new BN(10000)), { from: darren }),
    //                 "ERC721: owner query for nonexistent token"
    //             )
    //         })

    //         it("should not allow claim USDC reward", async () => {
    //             await expectRevert(
    //                 stakePool.claimReward(usdc.address, 23, web3.utils.toWei(new BN(10000)), { from: darren }),
    //                 "ERC721: owner query for nonexistent token"
    //             )
    //         })
    //     })
    // })
})
