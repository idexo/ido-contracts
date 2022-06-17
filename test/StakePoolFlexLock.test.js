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
        const minPoolStakeAmount = web3.utils.toWei(new BN(10000))
        ido = await ERC20.new("Idexo Community", "IDO", { from: owner })
        usdt = await ERC20.new("USD Tether", "USDT", { from: owner })
        usdc = await ERC20.new("USDC Coin", "USDC", { from: owner })
        stakePool = await StakePool.new("Idexo Stake Token", "IDS", DOMAIN, ido.address, usdt.address, { from: owner })
    })

    describe("# Get Contract info", async () => {
        it("should get depositToken", async () => {
            await stakePool.depositToken().then((res) => {
                expect(res.toString()).to.eq(ido.address)
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
            await stakePool.addStakeType("MONTHLY", 31, { from: owner })
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
                await stakePool.getStakeInfo(1).then((res) => {
                    expect(res[0].toString()).to.eq("500000000000000000000")
                })

                await stakePool.getStakeType(1).then((res) => {
                    expect(res).to.eq("MONTHLY")
                    console.log(res)
                })

                await stakePool.currentSupply().then((res) => {
                    expect(res.toString()).to.eq("1")
                })

                await stakePool.setCompounding(1, true)

                await stakePool.isCompounding(1).then((res) => {
                    expect(res).to.eq(true)
                })
            })
            it("should stake 2", async () => {
                await stakePool.getEligibleStakeAmount(0, { from: carol }).then((res) => {
                    expect(res.toString()).to.eq("0")
                })
                let number = await ethers.provider.getBlockNumber()
                let block = await ethers.provider.getBlock(number)
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(5000)), "MONTHLY", true, { from: carol }), "Deposited")
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
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(5000)), "MONTHLY", true, { from: carol }), "Deposited")
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

            describe("# Withdraw", async () => {
                it("should revert withdraw stake 3 if LOCKED_FOR_WITHDRAWN", async () => {
                    await ido.balanceOf(stakePool.address).then((res) => {
                        expect(res.toString()).to.eq("10500000000000000000000")
                    })
                    await timeTraveler.advanceTimeAndBlock(duration.days(29))
                    await expectRevert(
                        stakePool.withdraw(3, web3.utils.toWei(new BN(5000)), { from: carol }),
                        "StakePool#withdraw: STAKE_STILL_LOCKED_FOR_WITHDRAWAL"
                    )
                    await timeTraveler.advanceTimeAndBlock(duration.days(-29))
                })

                it("should withdraw stake 3 after unlocked", async () => {
                    await timeTraveler.advanceTimeAndBlock(duration.days(31))
                    expectEvent(await stakePool.withdraw(3, web3.utils.toWei(new BN(5000)), { from: carol }), "Withdrawn")
                    await stakePool.isHolder(carol).then((res) => {
                        expect(res.toString()).to.eq("true")
                    })
                    await timeTraveler.advanceTimeAndBlock(duration.days(-31))
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
})
