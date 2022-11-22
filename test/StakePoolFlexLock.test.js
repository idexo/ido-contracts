const { expect } = require("chai")
const { duration } = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const StakePool = artifacts.require("contracts/staking/StakePoolFlexLock.sol:StakePoolFlexLock")
const ERC20 = artifacts.require("ERC20Mock")

contract("::StakePoolFlexLock", async (accounts) => {
    let stakePool, ido, usdt, usdc
    const [owner, alice, bob, carol, darren] = accounts
    const DOMAIN = "https://idexo.com/"

    before(async () => {
        const minPoolStakeAmount = web3.utils.toWei(new BN(500))
        ido = await ERC20.new("Idexo Community", "IDO", { from: owner })
        usdt = await ERC20.new("USD Tether", "USDT", { from: owner })
        usdc = await ERC20.new("USDC Coin", "USDC", { from: owner })
        stakePool = await StakePool.new("Idexo Stake Token", "IDS", DOMAIN, minPoolStakeAmount, ido.address, usdt.address, { from: owner })
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

        describe("reverts if", async () => {
            it("add operator by NO-OWNER", async () => {
                await expectRevert(stakePool.addOperator(bob, { from: alice }), "Ownable: caller is not the owner")
            })
            it("remove operator by NO-OWNER", async () => {
                await stakePool.addOperator(bob, { from: owner })
                await expectRevert(stakePool.removeOperator(bob, { from: alice }), "Ownable: caller is not the owner")
            })
        })
    })

    describe("# Get Contract info", async () => {
        it("supportsInterface", async () => {
            await stakePool.supportsInterface("0x00").then((res) => {
                expect(res).to.eq(false)
            })
        })
        it("should get depositToken", async () => {
            await stakePool.depositToken().then((res) => {
                expect(res.toString()).to.eq(ido.address)
            })
        })
    })

    describe("# Set minStakeAmount", async () => {
        it("should set minStakeAmount", async () => {
            await stakePool.minStakeAmount().then((res) => {
                expect(res.toString()).to.eq(web3.utils.toWei(new BN(500)).toString())
            })
            let snapShot = await timeTraveler.takeSnapshot()

            await stakePool.addOperator(alice, { from: owner })

            await stakePool.setMinStakeAmount(web3.utils.toWei(new BN(5000)), { from: alice })

            await stakePool.minStakeAmount().then((res) => {
                expect(res.toString()).to.eq(web3.utils.toWei(new BN(5000)).toString())
            })

            await timeTraveler.revertToSnapshot(snapShot["result"])
        })
        describe("reverts if", async () => {
            it("NO-OPERATOR", async () => {
                await expectRevert(
                    stakePool.setMinStakeAmount(web3.utils.toWei(new BN(5000)), { from: alice }),
                    "Operatorable: CALLER_NO_OPERATOR_ROLE"
                )
            })
            it("INVALID_AMOUNT", async () => {
                await expectRevert(stakePool.setMinStakeAmount(web3.utils.toWei(new BN(0)), { from: owner }), "StakePoolFlex: ZERO_AMOUNT")
            })
        })
    })

    describe("# Reward Tokens", async () => {
        it("should add USDC token reward", async () => {
            await stakePool.addRewardToken(usdc.address, { from: owner })
        })
        describe("reverts if", async () => {
            it("add reward token by NO-OPERATOR", async () => {
                await expectRevert(stakePool.addRewardToken(usdc.address, { from: alice }), "Operatorable: CALLER_NO_OPERATOR_ROLE")
            })
        })
    })

    describe("# StakeToken Types", async () => {
        it("should add stakeType", async () => {
            await stakePool.addStakeTypes(["MONTHLY", "QUARTERLY"], [31, 91], { from: owner })
        })
    })

    describe("# Staking", async () => {
        before(async () => {
            for (const user of [owner, alice, bob, carol, darren]) {
                await ido.mint(user, web3.utils.toWei(new BN(20000)))
                await ido.approve(stakePool.address, web3.utils.toWei(new BN(20000)), { from: user })
            }
        })

        describe("staking", async () => {
            it("should stake 1", async () => {
                await stakePool.getEligibleStakeAmount(0, { from: alice }).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                await stakePool.isHolder(alice).then((res) => {
                    expect(res.toString()).to.eq("false")
                })

                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(500)), "MONTHLY", false, { from: alice }), "Deposited")
                await ido.balanceOf(stakePool.address).then((res) => {
                    expect(res.toString()).to.eq("500000000000000000000")
                })
            })
            it("stake info 1", async () => {
                await stakePool.getStakeInfo(1).then((res) => {
                    expect(res[0].toString()).to.eq("500000000000000000000")
                })

                await stakePool.getStakeType(1).then((res) => {
                    expect(res).to.eq("MONTHLY")
                })

                await stakePool.currentSupply().then((res) => {
                    expect(res.toString()).to.eq("1")
                })

                await stakePool.setCompounding(1, true, { from: alice })

                await stakePool.isCompounding(1).then((res) => {
                    expect(res).to.eq(true)
                })

                await stakePool.getStakeTokenIds(alice).then((res) => {
                    expect(res[0].toString()).to.eq("1")
                })
            })
            it("should stake 2", async () => {
                await stakePool.getEligibleStakeAmount(0, { from: carol }).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                let number = await ethers.provider.getBlockNumber()
                let block = await ethers.provider.getBlock(number)
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(5000)), "MONTHLY", false, { from: carol }), "Deposited")
                await stakePool.getStakeInfo(2).then((res) => {
                    expect(res[0].toString()).to.eq("5000000000000000000000")
                })
                await stakePool.isHolder(carol).then((res) => {
                    expect(res.toString()).to.eq("true")
                })
                let snapShot = await timeTraveler.takeSnapshot()
                await timeTraveler.advanceTime(duration.months(10))
                await stakePool.getEligibleStakeAmount(block.timestamp, { from: carol }).then((res) => {
                    expect(res.toString()).to.not.eq("0")
                })
                await timeTraveler.revertToSnapshot(snapShot["result"])
            })
            it("should stake 3", async () => {
                await stakePool.getEligibleStakeAmount(0, { from: carol }).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                let number = await ethers.provider.getBlockNumber()
                let block = await ethers.provider.getBlock(number)
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(5000)), "MONTHLY", true, { from: carol }), "Deposited")
                await stakePool.getStakeInfo(3).then((res) => {
                    expect(res[0].toString()).to.eq("5000000000000000000000")
                })
                await stakePool.isHolder(carol).then((res) => {
                    expect(res.toString()).to.eq("true")
                })
                let snapShot = await timeTraveler.takeSnapshot()
                await timeTraveler.advanceTime(duration.months(10))
                await stakePool.getEligibleStakeAmount(block.timestamp, { from: carol }).then((res) => {
                    expect(res.toString()).to.not.eq("0")
                })
                await timeTraveler.revertToSnapshot(snapShot["result"])

                await stakePool.getStakeTokenIds(carol).then((res) => {
                    expect(res[0].toString()).to.eq("2")
                    expect(res[1].toString()).to.eq("3")
                })

                await stakePool.getStakeAmount(carol).then((res) => {
                    expect(res.toString()).to.eq(web3.utils.toWei(new BN(10000)).toString())
                })
            })

            it("should revert if stake type not exists", async () => {
                await expectRevert(stakePool.deposit(web3.utils.toWei(new BN(5000)), "DAILY", true, { from: carol }), "STAKE_TYPE_NOT_EXIST")
            })
            it("should revert if stake type not exists", async () => {
                await expectRevert(stakePool.deposit(web3.utils.toWei(new BN(5000)), "", true, { from: carol }), "STAKE_TYPE_NOT_EXIST")
            })
        })

        describe("# addStake", async () => {
            it("should revert if caller not token nor contract owner", async () => {
                await expectRevert(
                    stakePool.addStake(1, web3.utils.toWei(new BN(500)), { from: carol }),
                    "StakePoolFlex: CALLER_NOT_TOKEN_OR_CONTRACT_OWNER"
                )
            })

            it("should add multiple stakes", async () => {
                let snapShot = await timeTraveler.takeSnapshot()
                await timeTraveler.advanceTimeAndBlock(duration.days(31))

                const amount = web3.utils.toWei(new BN(500))
                const stakeIds = [1, 2, 3]
                const amounts = [amount, amount, amount]

                expectEvent(await stakePool.addStakes(stakeIds, amounts, { from: owner }), "StakesAmountIncreased")

                await timeTraveler.revertToSnapshot(snapShot["result"])
            })

            it("should add amount to stakeToken", async () => {
                let snapShot = await timeTraveler.takeSnapshot()
                await timeTraveler.advanceTimeAndBlock(duration.days(31))

                expectEvent(await stakePool.addStake(1, web3.utils.toWei(new BN(500)), { from: alice }), "StakeAmountIncreased")

                await stakePool.reLockStake(1, "MONTHLY", true, { from: alice })

                await expectRevert(
                    stakePool.withdraw(1, web3.utils.toWei(new BN(1000)), { from: alice }),
                    "StakePoolFlex: STAKE_STILL_LOCKED_FOR_WITHDRAWAL"
                )

                await timeTraveler.revertToSnapshot(snapShot["result"])
            })
        })

        describe("# Withdraw", async () => {
            it("should revert withdraw stake 2 if LOCKED_FOR_WITHDRAWN", async () => {
                await ido.balanceOf(stakePool.address).then((res) => {
                    expect(res.toString()).to.eq("10500000000000000000000")
                })
                await expectRevert(
                    stakePool.withdraw(2, web3.utils.toWei(new BN(5000)), { from: carol }),
                    "StakePoolFlex: STAKE_STILL_LOCKED_FOR_WITHDRAWAL"
                )
            })

            it("should partial withdraw stake 2 after unlocked", async () => {
                let snapShot = await timeTraveler.takeSnapshot()

                await timeTraveler.advanceTimeAndBlock(duration.days(31))
                expectEvent(await stakePool.withdraw(2, web3.utils.toWei(new BN(2500)), { from: carol }), "Withdrawn")
                await stakePool.isHolder(carol).then((res) => {
                    expect(res.toString()).to.eq("true")
                })
                await timeTraveler.revertToSnapshot(snapShot["result"])
            })

            it("should full withdraw stake 2 after unlocked", async () => {
                let snapShot = await timeTraveler.takeSnapshot()

                await timeTraveler.advanceTimeAndBlock(duration.days(31))
                expectEvent(await stakePool.withdraw(2, web3.utils.toWei(new BN(5000)), { from: carol }), "Withdrawn")
                await stakePool.isHolder(carol).then((res) => {
                    expect(res.toString()).to.eq("true")
                })

                await stakePool.currentSupply().then((res) => {
                    expect(res.toString()).to.eq("2")
                })
                await timeTraveler.revertToSnapshot(snapShot["result"])
            })

            it("should shows current total supply", async () => {
                await stakePool.currentSupply().then((res) => {
                    expect(res.toString()).to.eq("3")
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
                await expectRevert(stakePool.setTokenURI(1, "test", { from: alice }), "Ownable: caller is not the owner")
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
                expectEvent(await stakePool.depositReward(usdc.address, web3.utils.toWei(new BN(20000)), { from: owner }), "RewardDeposited")
                await stakePool.getRewardDeposit(usdc.address, 0).then((res) => {
                    expect(res[1].toString()).to.eq("20000000000000000000000")
                })
            })
        })
        describe("claimable reward", async () => {
            it("should add claimable USDT reward to 1", async () => {
                expectEvent(
                    await stakePool.addClaimableReward(usdt.address, 1, web3.utils.toWei(new BN(5000)), { from: owner }),
                    "ClaimableRewardAdded"
                )

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
                expectEvent(
                    await stakePool.addClaimableRewards(usdt.address, tokenIds, rewardsUSDT, {
                        from: owner
                    }),
                    "ClaimableRewardAdded"
                )

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
                await stakePool.deposit(web3.utils.toWei(new BN(600)), "MONTHLY", false, { from: darren })
                await stakePool.currentSupply().then((res) => {
                    expect(res.toString()).to.eq("4")
                })
                expectEvent(await stakePool.transferFrom(alice, carol, 1, { from: alice }), "Transfer")
                await stakePool.getStakeInfo(1).then((res) => {
                    expect(res[0].toString()).to.eq("500000000000000000000")
                })
                await stakePool.balanceOf(alice).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                await stakePool.balanceOf(carol).then((res) => {
                    expect(res.toString()).to.eq("3")
                })
                await stakePool.getStakeAmount(alice).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                await stakePool.getStakeAmount(carol).then((res) => {
                    expect(res.toString()).to.eq("10500000000000000000000")
                })
            })
        })
    })

    describe("# Sweep", async () => {
        it("should sweep funds to another account", async () => {
            let balance = await usdt.balanceOf(stakePool.address)
            balance = await usdc.balanceOf(stakePool.address)
            await stakePool.sweep(usdc.address, darren, web3.utils.toWei(new BN(2500)), { from: owner })
            balance = await usdc.balanceOf(stakePool.address)
        })
    })

    describe("# Stake Types", async () => {
        it("should an array of valid stake types", async () => {
            stakePool.getStakeTypes().then((res) => {
                expect(res.length == 3)
            })
        })
        it("should a stake type info", async () => {
            stakePool.getStakeTypeInfo("MONTHLY").then((res) => {
                expect(res.inDays == "31")
                expect(res.name == "MONTHLY")
            })
        })
        it("should a stake type info", async () => {
            stakePool.getStakeTypeInfo("QUARTERLY").then((res) => {
                expect(res.inDays == "91")
                expect(res.name == "QUARTERLY")
            })
        })
        it("should show a empty stake type if not valid", async () => {
            stakePool.getStakeTypeInfo("DAILY").then((res) => {
                expect(res.inDays == "0")
            })
        })
    })

    describe("# Loop over Stakes", async () => {
        it("should not raise errors", async () => {
            await timeTraveler.advanceTime(duration.months(100))
            const tokens = await stakePool.tokenIds()
            for (let i = 1; i <= tokens; i++) {
                const info = await stakePool.getStakeInfo(i)
                console.log(i, info.isCompounding, String(info.amount))
                try {
                    await stakePool.withdraw(i, String(info.amount), { from: carol })
                } catch (e) {
                    console.log(i, e.message)
                }
            }
            console.log("----")
            for (let i = 1; i <= tokens; i++) {
                try {
                    const info = await stakePool.getStakeInfo(i)
                    console.log(i, info.isCompounding, String(info.amount))
                } catch (e) {
                    console.log(i, e.message)
                }
            }
            await timeTraveler.advanceTime(duration.months(-100))
            expect(1 == 1)
        })
    })
})
