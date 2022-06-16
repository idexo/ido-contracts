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
        it("should get depositToken", async () => {
            await stakePool.depositToken().then((res) => {
                expect(res.toString()).to.eq(ido.address)
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
})
