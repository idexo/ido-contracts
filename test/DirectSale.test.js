const { expect } = require("chai")
const { duration } = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const DirectSale = artifacts.require("contracts/marketplace/direct/DirectSale.sol:DirectSale")
const ERC20 = artifacts.require("ERC20Mock")
const CommunityNFT = artifacts.require("CommunityNFT")
const RoyaltyNFT = artifacts.require("contracts/marketplace/direct/RoyaltyNFT.sol:RoyaltyNFT")

contract("::DirectSale", async (accounts) => {
    let directSale, royaltyNFT, nft, ido, usdt, usdc
    const [owner, alice, bob, carol, darren] = accounts
    const DOMAIN = "https://idexo.com/"
    const startTime = Math.floor(Date.now() / 1000) + duration.seconds(10)

    before(async () => {
        ido = await ERC20.new("Idexo Community", "IDO", { from: owner })
        royaltyNFT = await RoyaltyNFT.new("RoyaltyNFT", "RNFT", DOMAIN, owner, 1, { from: owner })
        nft = await CommunityNFT.new("TEST", "T", DOMAIN, { from: owner })
        directSale = await DirectSale.new(ido.address, startTime, { from: owner })
    })

    describe("# SaleStartTime", async () => {
        it("should set sale start time", async () => {
            await directSale.setSaleStartTime(Math.floor(Date.now() / 1000) + duration.seconds(10), { from: owner })
        })
        // it("should get minPoolStakeAmount", async () => {
        //     await directSale.minPoolStakeAmount().then((res) => {
        //         expect(res.toString()).to.eq(web3.utils.toWei(new BN(10000)).toString())
        //     })
        // })
        // it("should get timeLimit", async () => {
        //     await directSale.timeLimit().then((res) => {
        //         expect(res.toString()).to.eq("0")
        //     })
        // })
        // it("should get depositToken", async () => {
        //     await directSale.depositToken().then((res) => {
        //         expect(res.toString()).to.eq(ido.address)
        //     })
        // })
    })

    // describe("# Staking", async () => {
    //     before(async () => {
    //         for (const user of [alice, bob, carol, darren]) {
    //             await ido.mint(user, web3.utils.toWei(new BN(20000)))
    //             await ido.approve(directSale.address, web3.utils.toWei(new BN(20000)), { from: user })
    //         }
    //     })

    //     describe("staking", async () => {
    //         it("should stake 1", async () => {
    //             await directSale.getEligibleStakeAmount(0, { from: alice }).then((res) => {
    //                 expect(res.toString()).to.eq("0")
    //             })
    //             await directSale.isHolder(alice).then((res) => {
    //                 expect(res.toString()).to.eq("false")
    //             })
    //             expectEvent(await directSale.deposit(web3.utils.toWei(new BN(500)), 0, { from: alice }), "Deposited")
    //             await ido.balanceOf(directSale.address).then((res) => {
    //                 expect(res.toString()).to.eq("500000000000000000000")
    //             })
    //             await directSale.getStakeInfo(1).then((res) => {
    //                 expect(res[0].toString()).to.eq("500000000000000000000")
    //             })
    //         })
    //         it("should stake 2", async () => {
    //             await directSale.getEligibleStakeAmount(0, { from: carol }).then((res) => {
    //                 expect(res.toString()).to.eq("0")
    //             })
    //             let number = await ethers.provider.getBlockNumber()
    //             let block = await ethers.provider.getBlock(number)
    //             expectEvent(await directSale.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }), "Deposited")
    //             await directSale.getStakeInfo(2).then((res) => {
    //                 expect(res[0].toString()).to.eq("5000000000000000000000")
    //             })
    //             await directSale.isHolder(carol).then((res) => {
    //                 expect(res.toString()).to.eq("true")
    //             })
    //             await timeTraveler.advanceTime(duration.months(10))
    //             await directSale.getEligibleStakeAmount(block.timestamp, { from: carol }).then((res) => {
    //                 expect(res.toString()).to.not.eq("0")
    //             })
    //             await timeTraveler.advanceTime(duration.months(-10))
    //         })
    //         it("should stake 3", async () => {
    //             await directSale.getEligibleStakeAmount(0, { from: carol }).then((res) => {
    //                 expect(res.toString()).to.eq("0")
    //             })
    //             let number = await ethers.provider.getBlockNumber()
    //             let block = await ethers.provider.getBlock(number)
    //             expectEvent(await directSale.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }), "Deposited")
    //             await directSale.getStakeInfo(3).then((res) => {
    //                 expect(res[0].toString()).to.eq("5000000000000000000000")
    //             })
    //             await directSale.isHolder(carol).then((res) => {
    //                 expect(res.toString()).to.eq("true")
    //             })
    //             await timeTraveler.advanceTime(duration.months(10))
    //             await directSale.getEligibleStakeAmount(block.timestamp, { from: carol }).then((res) => {
    //                 expect(res.toString()).to.not.eq("0")
    //             })
    //             await timeTraveler.advanceTime(duration.months(-10))
    //         })

    //         describe("should withdraw before and after pool closed", async () => {
    //             it("should withdraw stake 3 before", async () => {
    //                 expectEvent(await directSale.withdraw(3, web3.utils.toWei(new BN(5000)), { from: carol }), "Withdrawn")
    //                 await directSale.isHolder(carol).then((res) => {
    //                     expect(res.toString()).to.eq("true")
    //                 })
    //                 await directSale.timeLimit().then((res) => {
    //                     expect(res.toString()).to.eq("0")
    //                 })
    //             })
    //             it("should stake 4", async () => {
    //                 await directSale.deposit(web3.utils.toWei(new BN(600)), 0, { from: darren })
    //             })
    //             it("should withdraw stake 5 after pool closed", async () => {
    //                 expectEvent(await directSale.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }), "Deposited")
    //                 await timeTraveler.advanceTimeAndBlock(duration.days(1))
    //                 expectEvent(await directSale.withdraw(5, web3.utils.toWei(new BN(5000)), { from: carol }), "Withdrawn")
    //                 await directSale.timeLimit().then((res) => {
    //                     expect(res.toString()).to.not.eq("0")
    //                 })
    //                 await timeTraveler.advanceTimeAndBlock(duration.days(-1))
    //             })
    //         })

    //         describe("should revert stake after pool closed", async () => {
    //             it("should revert stake 5 if DEPOSIT_TIME_CLOSED", async () => {
    //                 await ido.balanceOf(directSale.address).then((res) => {
    //                     expect(res.toString()).to.eq("6100000000000000000000")
    //                 })
    //                 await timeTraveler.advanceTimeAndBlock(duration.days(1))
    //                 await expectRevert(
    //                     directSale.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }),
    //                     "DirectSale#_deposit: DEPOSIT_TIME_CLOSED"
    //                 )
    //                 await timeTraveler.advanceTimeAndBlock(duration.days(-1))
    //             })
    //         })
    //     })
    // })
})
