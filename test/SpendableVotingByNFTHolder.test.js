const Voting = artifacts.require("contracts/voting/SpendableVotingByNFTHolder.sol")
const StakePool = artifacts.require("StakePool")
const ERC20 = artifacts.require("ERC20Mock")

const { Contract } = require("@ethersproject/contracts")
const { expect } = require("chai")
const { BN, constants, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const { toWei } = require("web3-utils")
const time = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")

contract("Voting", async (accounts) => {
    let ido, erc20
    let voting, sPool1, sPool2, sPool3, sPool4
    const [alice, bob, carol] = accounts

    before(async () => {
        ido = await ERC20.new("Idexo Community", "IDO", { from: alice })
        erc20 = await ERC20.new("USD Tether", "USDT", { from: alice })
        sPool1 = await StakePool.new("Idexo Stake Token", "IDS", "", ido.address, erc20.address)
        sPool2 = await StakePool.new("Idexo Stake Token", "IDS", "", ido.address, erc20.address)
        sPool3 = await StakePool.new("Idexo Stake Token", "IDS", "", ido.address, erc20.address)
        sPool4 = await StakePool.new("Idexo Stake Token", "IDS", "", ido.address, erc20.address)
        voting = await Voting.new(15, 15, [sPool1.address, sPool2.address])
    })

    describe("#Role", async () => {
        it("should add operator", async () => {
            await voting.addOperator(bob)
            expect(await voting.checkOperator(bob)).to.eq(true)
        })
        it("should remove operator", async () => {
            await voting.removeOperator(bob)
            expect(await voting.checkOperator(bob)).to.eq(false)
        })
        describe("reverts if", async () => {
            it("add operator by non-admin", async () => {
                await expectRevert(voting.addOperator(bob, { from: bob }), "Ownable: caller is not the owner")
            })
            it("remove operator by non-admin", async () => {
                await voting.addOperator(bob)
                await expectRevert(voting.removeOperator(bob, { from: bob }), "Ownable: caller is not the owner")
            })
        })
    })

    describe("#Get", async () => {
        it("getReviewIds", async () => {
            expect(Number(await voting.getReviewIds(1))).to.eq(0)
        })
        it("getReview", async () => {
            await expectRevert(voting.getReview(1, 1), "INVALID_PROPOSAL")
        })
    })
})
