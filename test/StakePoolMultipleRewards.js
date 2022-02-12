const { expect } = require("chai")
const { duration } = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const StakePool = artifacts.require("contracts/staking/StakePoolMultipleRewardsV1.sol:StakePoolMultipleRewardsV1")
const ERC20 = artifacts.require("ERC20Mock")

contract("::StakePoolMultipleRewards", async (accounts) => {
    let stakePool, ido, usdt, usdc
    const [owner, alice, bob, carol, darren] = accounts
    const DOMAIN = "https://idexo.com/"

    before(async () => {
        ido = await ERC20.new("Idexo Community", "IDO", { from: owner })
        usdt = await ERC20.new("USD Tether", "USDT", { from: owner })
        usdc = await ERC20.new("USDC Coin", "USDC", { from: owner })
        stakePool = await StakePool.new("Idexo Stake Token", "IDS", DOMAIN, ido.address, usdt.address, usdt.address, { from: owner })
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
            it("add operator by NO-ADMIN", async () => {
                await expectRevert(stakePool.addOperator(bob, { from: alice }), "StakePool#onlyAdmin: CALLER_NO_ADMIN_ROLE")
            })
            it("remove operator by NO-ADMIN", async () => {
                await stakePool.addOperator(bob, { from: owner })
                await expectRevert(stakePool.removeOperator(bob, { from: alice }), "StakePool#onlyAdmin: CALLER_NO_ADMIN_ROLE")
            })
        })
    })

    describe("# Reward Tokens", async () => {
        it("should add token reward", async () => {
            await stakePool.addRewardToken(usdc.address, usdc.address, { from: bob })
        })
        describe("reverts if", async () => {
            it("add reward token by NO-OPERATOR", async () => {
                await expectRevert(
                    stakePool.addRewardToken(usdc.address, usdc.address, { from: alice }),
                    "StakePool#onlyOperator: CALLER_NO_OPERATOR_ROLE"
                )
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
            it("should stake", async () => {
                await stakePool.getEligibleStakeAmount(0, { from: alice }).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                await stakePool.isHolder(alice).then((res) => {
                    expect(res.toString()).to.eq("false")
                })
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(3000)), 0, { from: alice }), "Deposited")
                await stakePool.getStakeInfo(1).then((res) => {
                    expect(res[0].toString()).to.eq("3000000000000000000000")
                })
            })
            it("should change tokenURI", async () => {
                await stakePool.setTokenURI(1, "test", { from: owner }),
                    await stakePool.tokenURI(1).then((res) => {
                        expect(res.toString()).to.eq(DOMAIN + "test")
                    })
            })
        })
    })

    describe("# Withdraw", async () => {
        describe("withdraws", async () => {
            it("should withdraw", async () => {
                expectEvent(await stakePool.withdraw(1, web3.utils.toWei(new BN(1000)), { from: alice }), "StakeAmountDecreased")
                await stakePool.getStakeInfo(1).then((res) => {
                    expect(res[0].toString()).to.eq("2000000000000000000000")
                })
            })
        })
    })

    describe("# Rewards", async () => {
        before(async () => {
            for (const user of [owner, alice, bob]) {
                await usdt.mint(user, web3.utils.toWei(new BN(50000)), { from: owner })
                await usdt.approve(stakePool.address, web3.utils.toWei(new BN(50000)), { from: user })
                await usdc.mint(user, web3.utils.toWei(new BN(50000)), { from: owner })
                await usdc.approve(stakePool.address, web3.utils.toWei(new BN(50000)), { from: user })
            }
        })
        describe("deposit and add claimable rewards", async () => {
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
            it("should add claimable USDT reward", async () => {
                await stakePool.addClaimableReward(usdt.address, 1, web3.utils.toWei(new BN(50000)), { from: owner })
                await stakePool.getClaimableReward(usdt.address, 1).then((res) => {
                    expect(res.toString()).to.eq("50000000000000000000000")
                })
            })
            it("should add claimable USDC reward", async () => {
                await stakePool.addClaimableReward(usdc.address, 1, web3.utils.toWei(new BN(20000)), { from: owner })
                await stakePool.getClaimableReward(usdc.address, 1).then((res) => {
                    expect(res.toString()).to.eq("20000000000000000000000")
                })
            })
        })
        describe("claim rewards", async () => {
            it("should allow claim reward", async () => {
                expectEvent(await stakePool.claimReward(usdt.address, 1, web3.utils.toWei(new BN(3000)), { from: alice }), "RewardClaimed")
            })
        })

        describe("transfer", async () => {})
    })

    describe("# Transfer", async () => {
        describe("transfers", async () => {
            it("should transfer", async () => {
                await stakePool.deposit(web3.utils.toWei(new BN(600)), 0, { from: darren })
                await stakePool.currentSupply().then((res) => {
                    expect(res.toString()).to.eq("2")
                })
                expectEvent(await stakePool.transferFrom(alice, carol, 1, { from: alice }), "Transfer")
                await stakePool.getStakeInfo(1).then((res) => {
                    expect(res[0].toString()).to.eq("2000000000000000000000")
                })
                await stakePool.balanceOf(alice).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                await stakePool.balanceOf(carol).then((res) => {
                    expect(res.toString()).to.eq("1")
                })
                await stakePool.getStakeAmount(alice).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                await stakePool.getStakeAmount(carol).then((res) => {
                    expect(res.toString()).to.eq("2000000000000000000000")
                })
                await stakePool.getStakeTokenIds(carol).then((res) => {
                    expect(res.toString()).to.eq("1")
                })
            })
        })
    })

    // describe("withdraw max", async () => {
    //     it("should withdraw", async () => {
    //         expectEvent.notEmitted(await stakePool.withdraw(1, web3.utils.toWei(new BN(2000)), { from: carol }), "StakeAmountDecreased")
    //         await stakePool.getStakeAmount(carol).then((res) => {
    //             expect(res.toString()).to.eq("0")
    //         })
    //     })
    //     it("multiple deposits", async () => {
    //         for (let i = 0; i <= 5; i++) {
    //             for (const user of [alice, bob, carol]) {
    //                 await stakePool.deposit(web3.utils.toWei(new BN(600)), 0, { from: user })
    //             }
    //         }
    //         for (const user of [bob, alice, carol]) {
    //             await stakePool.getStakeAmount(user).then((res) => {
    //                 expect(res.toString()).to.not.eq("0")
    //             })
    //             let res = await stakePool.getStakeTokenIds(user)
    //             for (const id of res.toString().split(",")) {
    //                 await stakePool.withdraw(id, web3.utils.toWei(new BN(600)), { from: user })
    //             }
    //             await stakePool.getStakeAmount(user).then((res) => {
    //                 expect(res.toString()).to.eq("0")
    //             })
    //         }
    //     })
    // })

    describe("deposit with timestamplock", async () => {
        it("should deposit", async () => {
            const number = await ethers.provider.getBlockNumber()
            const block = await ethers.provider.getBlock(number)
            expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(3000)), block.timestamp + duration.days(3), { from: alice }), "Deposited")
        })
        it("should not allow withdraw", async () => {
            let res = await stakePool.getStakeTokenIds(alice)
            for (const id of res.toString().split(",")) {
                await expectRevert(
                    stakePool.withdraw(id, web3.utils.toWei(new BN(1000)), { from: alice }),
                    "StakePool#withdraw: STAKE_STILL_LOCKED_FOR_WITHDRAWAL"
                )
            }
        })
        it("should allow withdraw", async () => {
            timeTraveler.advanceTime(duration.months(1))
            let res = await stakePool.getStakeTokenIds(alice)
            for (const id of res.toString().split(",")) {
                expectEvent(await stakePool.withdraw(id, web3.utils.toWei(new BN(1000)), { from: alice }), "StakeAmountDecreased")
            }
            timeTraveler.advanceTime(duration.months(-1))
        })
    })
})
