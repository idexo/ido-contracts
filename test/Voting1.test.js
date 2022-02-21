const Voting1 = artifacts.require("contracts/voting/Voting1.sol:Voting1")
const StakePool = artifacts.require("StakePool")
const ERC20 = artifacts.require("ERC20Mock")

const { expect } = require("chai")
const { BN, constants, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const { toWei } = require("web3-utils")
const time = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")

contract("Voting1", async (accounts) => {
    let ido, erc20
    let voting1, sPool1, sPool2, sPool3
    const [alice, bob, carol] = accounts

    before(async () => {
        ido = await ERC20.new("Idexo Community", "IDO", { from: alice })
        erc20 = await ERC20.new("USD Tether", "USDT", { from: alice })
        sPool1 = await StakePool.new("Idexo Stake Token", "IDS", ido.address, erc20.address)
        sPool2 = await StakePool.new("Idexo Stake Token", "IDS", ido.address, erc20.address)
        sPool3 = await StakePool.new("Idexo Stake Token", "IDS", ido.address, erc20.address)
        voting1 = await Voting1.new([sPool1.address, sPool2.address], toWei(new BN(400000)), new BN(7), new BN(14))
    })

    describe("#Role", async () => {
        it("should add operator", async () => {
            await voting1.addOperator(bob)
            expect(await voting1.checkOperator(bob)).to.eq(true)
        })
        it("should remove operator", async () => {
            await voting1.removeOperator(bob)
            expect(await voting1.checkOperator(bob)).to.eq(false)
        })
        describe("reverts if", async () => {
            it("add operator by non-admin", async () => {
                await expectRevert(voting1.addOperator(bob, { from: bob }), "Voting1#onlyAdmin: CALLER_NO_ADMIN_ROLE")
            })
            it("remove operator by non-admin", async () => {
                await voting1.addOperator(bob)
                await expectRevert(voting1.removeOperator(bob, { from: bob }), "Voting1#onlyAdmin: CALLER_NO_ADMIN_ROLE")
            })
        })
    })

    describe("#StakePool", async () => {
        it("addStakePool", async () => {
            await voting1.addStakePool(sPool3.address, { from: bob })
            await voting1.getStakePools().then((res) => {
                expect(res.length).to.eq(3)
                expect(res[0]).to.eq(sPool1.address)
                expect(res[1]).to.eq(sPool2.address)
                expect(res[2]).to.eq(sPool3.address)
            })
        })
        it("removeStakePool", async () => {
            await voting1.removeStakePool(sPool3.address, { from: bob })
            await voting1.getStakePools().then((res) => {
                expect(res.length).to.eq(2)
                expect(res[0]).to.eq(sPool1.address)
            })
        })
        describe("reverts if", async () => {
            it("addStakePool removeStakePool", async () => {
                await expectRevert(voting1.addStakePool(sPool3.address, { from: carol }), "Voting1#onlyOperator: CALLER_NO_OPERATOR_ROLE")
                await expectRevert(voting1.addStakePool(constants.ZERO_ADDRESS, { from: bob }), "Voting1#addStakePool: STAKE_POOL_ADDRESS_INVALID")
                await expectRevert(voting1.addStakePool(sPool1.address, { from: bob }), "Voting1#addStakePool: STAKE_POOL_ADDRESS_ALREADY_FOUND")
                await expectRevert(voting1.removeStakePool(sPool3.address, { from: bob }), "Voting1#removeStakePool: STAKE_POOL_ADDRESS_NOT_FOUND")
            })
        })
    })

    describe("#Poll", async () => {
        before(async () => {
            await ido.mint(alice, toWei(new BN(10000000)))
            await ido.mint(bob, toWei(new BN(10000000)))
            await ido.approve(sPool1.address, toWei(new BN(10000000)), { from: alice })
            await ido.approve(sPool2.address, toWei(new BN(10000000)), { from: alice })
            await ido.approve(sPool1.address, toWei(new BN(10000000)), { from: bob })
            await ido.approve(sPool2.address, toWei(new BN(10000000)), { from: bob })
            await sPool1.deposit(toWei(new BN(4000)), { from: alice })
            await sPool1.deposit(toWei(new BN(7000)), { from: bob })
            await sPool2.deposit(toWei(new BN(8000)), { from: alice })
            await sPool2.deposit(toWei(new BN(14000)), { from: bob })
            await timeTraveler.advanceTime(time.duration.months(1))
        })
        it("createPoll castVote getWeight checkIfVoted endPoll", async () => {
            await voting1.createPoll("Solana Integration", new BN(30), { from: bob })
            await voting1.getPollInfo(1).then((res) => {
                expect(res[0]).to.eq("Solana Integration")
                expect(res[2].sub(res[1]).toString()).to.eq(time.duration.days(7).toString())
                expect(res[3].toString()).to.eq("30")
                expect(res[4].toString()).to.eq("0")
                expect(res[5]).to.eq(bob)
            })
            await voting1.getWeight.call(1, alice).then((res) => {
                expect(res.toString()).to.eq("12000000000000000000000")
            })
            expect(await voting1.checkIfVoted(1, alice)).to.eq(false)
            expectEvent(await voting1.castVote(1, true, { from: alice }), "VoteCasted")
            expect(await voting1.checkIfVoted(1, alice)).to.eq(true)
            await voting1.castVote(1, false, { from: bob })
            await voting1.getPollVotingInfo(1, { from: bob }).then((res) => {
                expect(res[0].toString()).to.eq("12000000000000000000000")
                expect(res[1].toString()).to.eq("21000000000000000000000")
                expect(res[2].toString()).to.eq("0")
            })
            await timeTraveler.advanceTime(time.duration.days(7))
            expectEvent(await voting1.endPoll(1, { from: bob }), "PollEnded", {
                pollID: new BN(1),
                status: new BN(2)
            })

            await voting1.createPoll("Tezos Integration", new BN(30), { from: bob })
            await voting1.castVote(2, true, { from: alice })
            await voting1.castVote(2, false, { from: bob })
            await expectRevert(voting1.endPoll(2, { from: bob }), "Voting1#endPoll: POLL_PERIOD_NOT_EXPIRED")
            await timeTraveler.advanceTime(time.duration.days(14))
            expectEvent(await voting1.endPoll(2, { from: bob }), "PollEnded", {
                pollID: new BN(2),
                status: new BN(2)
            })
        })
        describe("reverts if", async () => {
            it("createPoll", async () => {
                await expectRevert(
                    voting1.createPoll("Cardano Integration", new BN(30), { from: carol }),
                    "Voting1#onlyOperator: CALLER_NO_OPERATOR_ROLE"
                )
                await expectRevert(voting1.createPoll("", new BN(30), { from: bob }), "Voting1#createPoll: DESCRIPTION_INVALID")
                await voting1.createPoll("Cardano Integration", new BN(30), { from: bob })
                await expectRevert(voting1.getPollInfo(4), "Voting1#validPoll: POLL_ID_INVALID")
                await expectRevert(voting1.getWeight(3, constants.ZERO_ADDRESS), "Voting1#getWeight: ACCOUNT_INVALID")
                await expectRevert(voting1.endPoll(3), "Voting1#endPoll: POLL_PERIOD_NOT_EXPIRED")
                await voting1.castVote(3, true, { from: alice })
                await expectRevert(voting1.castVote(3, true, { from: alice }), "Voting1#castVote: USER_ALREADY_VOTED")
                await timeTraveler.advanceTime(time.duration.days(7))
                await voting1.endPoll(3, { from: bob })
                await expectRevert(voting1.castVote(3, true, { from: alice }), "Voting1#castVote: POLL_ALREADY_ENDED")
            })
        })
        describe("getters", async () => {
            it("getPollMinimumVotes", async () => {
                await voting1.setPollMinimumVotes(111, { from: bob })
                expect(String(await voting1.getPollMinimumVotes())).to.eq("111")
            })
            it("getPollMaximumDurationInDays", async () => {
                await voting1.setPollMaximumDurationInDays(112, { from: bob })
                expect(String(await voting1.getPollMaximumDurationInDays())).to.eq("112")
            })
            it("getPollDurationInDays", async () => {
                await voting1.setPollDurationInDays(113, { from: bob })
                expect(String(await voting1.getPollDurationInDays())).to.eq("113")
            })
            it("getVoterInfo", async () => {
                let vi = await voting1.getVoterInfo(1, alice)
                expect(vi["0"]).to.eq(true)
                expect(vi["1"]).to.eq(true)
                expect(String(vi["2"])).to.eq("12000000000000000000000")
            })
        })
        after(async () => {
            await timeTraveler.advanceTime(time.duration.months(-1))
        })
    })
})
