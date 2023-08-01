const Vesting = artifacts.require("contracts/vesting/Vesting.sol:Vesting")
const ERC20 = artifacts.require("ERC20Mock")

const { expect } = require("chai")
const timeTraveler = require("ganache-time-traveler")
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const time = require("./helpers/time")
const { web3 } = require("@openzeppelin/test-helpers/src/setup")

contract("::Vesting", async (accounts) => {
    let vestingERC20
    let erc20
    let currentBlockNumber
    let currentTimestamp
    let startTime

    const [alice, bob, carl] = accounts
    const erc20Name = "Idexo Token"
    const erc20Symbol = "IDO"
    const decimals = 18
    const cliff = 3 * 31 // 3 Months
    const duration = 9 * 31 // 9 Months
    const totalAmount = new BN(10).pow(new BN(decimals)).mul(new BN(1000000000))

    beforeEach(async () => {
        erc20 = await ERC20.new(erc20Name, erc20Symbol, { from: alice })
        currentBlockNumber = await web3.eth.getBlockNumber()
        await web3.eth.getBlock(currentBlockNumber).then((block) => {
            currentTimestamp = block.timestamp
        })
        startTime = currentTimestamp + time.duration.days(1)
        vestingERC20 = await Vesting.new(erc20.address, bob, startTime, cliff, duration, 1, { from: alice })
    })

   

    describe("#Vesting", async () => {
        describe("##Deposit initial funds", async () => {
            beforeEach(async () => {
                await erc20.mint(alice, totalAmount)
                await erc20.approve(vestingERC20.address, new BN(10).pow(new BN(decimals)).mul(new BN(10000000000)), { from: alice })
            })
            it("should deposit", async () => {
                expectEvent(await vestingERC20.depositInitial(totalAmount, { from: alice }), "InitialDeposited", {
                    operator: alice,
                    amount: totalAmount
                })
            })
            describe("reverts if", async () => {
                
                it("depositInitial twice", async () => {
                    await vestingERC20.depositInitial(totalAmount, { from: alice })
                    await expectRevert(vestingERC20.depositInitial(totalAmount, { from: alice }), "ALREADY_INITIAL_DEPOSITED")
                })
                it("deposit amount is 0", async () => {
                    await expectRevert(vestingERC20.depositInitial(0, { from: alice }), "AMOUNT_INVALID")
                })
                it("deposit amount is greater than operator balance", async () => {
                    await expectRevert(
                        vestingERC20.depositInitial(totalAmount.add(new BN(1500)), {
                            from: alice
                        }),
                        "ERC20: transfer amount exceeds balance"
                    )
                })
            })
        })

        describe("##VestedAmount", async () => {
            beforeEach(async () => {
                await erc20.mint(alice, totalAmount)
                await erc20.approve(vestingERC20.address, totalAmount, { from: alice })
                await vestingERC20.depositInitial(totalAmount, { from: alice })
            })
            it("should return 0 before start time", async () => {
                await vestingERC20.getVestedAmount().then((bn) => {
                    expect(bn.toNumber()).to.eq(0)
                })
            })
            it("should return 0 during cliff period", async () => {
                await timeTraveler.advanceTimeAndBlock(time.duration.months(2))
                await vestingERC20.getVestedAmount().then((bn) => {
                    expect(bn.toNumber()).to.eq(0)
                })
            })
            it("should return total amount after vesting is ended", async () => {
                await timeTraveler.advanceTimeAndBlock(time.duration.months(20))
                await vestingERC20.getVestedAmount().then((bn) => {
                    expect(bn.toString()).to.eq(totalAmount.toString())
                })
            })
            it("should return vested amount", async () => {
                await vestingERC20.getVestedAmount().then((bn) => {
                    expect(bn.toNumber()).to.eq(0)
                })
            })
        })

        describe("##Claim", async () => {
            beforeEach(async () => {
                await erc20.mint(alice, totalAmount)
                await erc20.approve(vestingERC20.address, totalAmount, { from: alice })
                await vestingERC20.depositInitial(totalAmount, { from: alice })
            })
            // it("should claim", async () => {
            //     await timeTraveler.advanceTimeAndBlock(time.duration.months(6))
            //     expectEvent(await vestingERC20.claim(new BN(100000), { from: bob }), "Claimed", {
            //         amount: new BN(100000)
            //     })
            // })
             it("should claim correct amount 25 days after cliff ends", async () => {
                await timeTraveler.advanceTimeAndBlock(time.duration.days(cliff + 25))
                let availableToClaim = await vestingERC20.getAvailableClaimAmount()
                expect(availableToClaim.toString()).to.not.eq("0")
                expectEvent(await vestingERC20.claim(availableToClaim, { from: bob }), "Claimed", {
                    amount: availableToClaim
                })
            })
            it("should claim correct amount 75 days after cliff ends", async () => {
                await timeTraveler.advanceTimeAndBlock(time.duration.days(cliff + 75))
                let availableToClaim = await vestingERC20.getAvailableClaimAmount()
                expect(availableToClaim.toString()).to.not.eq("0")
                expectEvent(await vestingERC20.claim(availableToClaim, { from: bob }), "Claimed", {
                    amount: availableToClaim
                })
            })
            it("should claim remaining amount at the end of claim period", async () => {
                await timeTraveler.advanceTimeAndBlock(time.duration.days(cliff + duration))
                let availableToClaim = await vestingERC20.getAvailableClaimAmount()
                expect(availableToClaim.toString()).to.eq(totalAmount.toString())
                expectEvent(await vestingERC20.claim(availableToClaim, { from: bob }), "Claimed", {
                    amount: availableToClaim
                })
            })
            describe("reverts if", async () => {
                it("non-beneficiary claim", async () => {
                    await expectRevert(vestingERC20.claim(new BN(10000), { from: carl }), "CALLER_NO_BENEFICIARY")
                })
                it("claim in cliff period", async () => {
                    await timeTraveler.advanceTimeAndBlock(time.duration.months(1))
                    await expectRevert(vestingERC20.claim(new BN(10000), { from: bob }), "CLIFF_PERIOD")
                })
                it("claim a day from last claim", async () => {
                    await timeTraveler.advanceTimeAndBlock(time.duration.months(6))
                    let availableToClaim = await vestingERC20.getAvailableClaimAmount()
                    expect(availableToClaim.toString()).to.not.eq("0")
                    await vestingERC20.claim(new BN(10000), { from: bob })
                    await expectRevert(vestingERC20.claim(new BN(10000), { from: bob }), "WITHIN_CLAIM_PERIOD_FROM_LAST_CLAIM")
                    availableToClaim = await vestingERC20.getAvailableClaimAmount()
                    expect(availableToClaim.toString()).to.eq("0")
                })
                it("claim amount is 0", async () => {
                    await timeTraveler.advanceTimeAndBlock(time.duration.months(6))
                    await expectRevert(vestingERC20.claim(new BN(0), { from: bob }), "AMOUNT_INVALID")
                })
                it("claim amount is greater than available amount", async () => {
                    await timeTraveler.advanceTimeAndBlock(time.duration.months(6))
                    let available = await vestingERC20.getVestedAmount()
                    await expectRevert(
                        vestingERC20.claim(available.add(new BN(111111111111111111111111n)), { from: bob }),
                        "AVAILABLE_CLAIM_AMOUNT_EXCEEDED"
                    )
                })
            })
        })

        describe("##Claim until 0", async () => {
            beforeEach(async () => {
                await erc20.mint(alice, totalAmount)
                await erc20.approve(vestingERC20.address, totalAmount, { from: alice })
                await vestingERC20.depositInitial(totalAmount, { from: alice })
            })
            it("should claim", async () => {
                for (let day = 0; day <= 403; day++) {
                    await timeTraveler.advanceTimeAndBlock(time.duration.days(1))
                    let availableToClaim = await vestingERC20.getAvailableClaimAmount()
                    if (day > 402) {
                        expect(availableToClaim.toString()).to.eq("0")
                    } else if (day < 123) {
                        await expectRevert(vestingERC20.claim(new BN(10000), { from: bob }), "CLIFF_PERIOD")
                    } else {
                        expectEvent(await vestingERC20.claim(availableToClaim.toString(), { from: bob }), "Claimed", {
                            amount: availableToClaim
                        })
                    }
                }
            })
        })
    })
})