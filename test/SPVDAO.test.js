const SPVDAO = artifacts.require("contracts/dao/SPVDAO.sol")
const StakePool = artifacts.require("StakePool")
const ERC20 = artifacts.require("ERC20Mock")

const { Contract } = require("@ethersproject/contracts")
const { expect } = require("chai")
const { BN, constants, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const { toWei } = require("web3-utils")
const time = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")
const { duration } = require("./helpers/time")

contract("Voting", async (accounts) => {
    let ido, spvdao
    const [alice, bob, carol] = accounts

    before(async () => {
        ido = await ERC20.new("Idexo Community", "IDO", { from: alice })
        await ido.mint(alice, web3.utils.toWei(new BN(100000)))
        spvdao = await SPVDAO.new("test", "T", "", 100, 1, ido.address, 15, 15, "description")
        await ido.approve(spvdao.address, web3.utils.toWei(new BN(100000)), { from: alice })
    })

    describe("#Inital tests", async () => {
        it("tokenURI", async () => {
            await expectRevert(spvdao.tokenURI(1), "ERC721: invalid token ID")
        })
        it("isHolder", async () => {
            expect(await spvdao.isHolder(bob)).to.eq(false)
        })
        it("voted", async () => {
            await expectRevert(spvdao.voted(1, bob), "INVALID_PROPOSAL")
        })
        it("getProposal", async () => {
            await expectRevert(spvdao.getProposal(0), "INVALID_PROPOSAL")
        })
        it("getReviewIds", async () => {
            expect(Number(await spvdao.getReviewIds(1))).to.eq(0)
        })
        it("getReview", async () => {
            await expectRevert(spvdao.getReview(1, 1), "INVALID_PROPOSAL")
        })
        it("getComments", async () => {
            expect((await spvdao.getComments(1)).length).to.eq(0)
        })
        it("getStakeTokenIds", async () => {
            expect(Number(await spvdao.getStakeTokenIds(bob))).to.eq(0)
        })
        it("getStakeAmount", async () => {
            expect(Number(await spvdao.getStakeAmount(bob))).to.eq(0)
        })
        it("getStakeInfo", async () => {
            await expectRevert(spvdao.getStakeInfo(1), "StakeToken#getStakeInfo: STAKE_NOT_FOUND")
        })
    })

    describe("#Proposal", async () => {
        it("createProposal", async () => {
            expectEvent(await spvdao.deposit(web3.utils.toWei(new BN(1000)), { from: alice }), "Deposited")
            expectEvent(await spvdao.createProposal("test", bob, 100, ido.address, 1, { from: alice }), "NewProposal")
            await spvdao.getProposal(1).then((res) => {
                expect(res[0].toString()).to.eq("test")
                expect(res.ended).to.eq(false)
            })
        })
        it("voteProposal", async () => {
            await spvdao.voteProposal(1, 1, 2, { from: alice })
            expect(await spvdao.isHolder(bob)).to.eq(false)
            expect(await spvdao.isHolder(alice)).to.eq(true)
            await spvdao.getProposal(1).then((res) => {
                let votes = res.options.reduce((a, c) => a + Number(c.votes), 0)
                expect(votes).to.greaterThan(1)
            })
        })
        it("endProposalVote", async () => {
            await expectRevert(spvdao.endProposalVote(1, { from: alice }), "OPEN_FOR_VOTE")
            await timeTraveler.advanceTime(duration.days(40))
            await spvdao.getProposal(1).then((res) => {
                expect(res.ended).to.eq(false)
            })
            await spvdao.endProposalVote(1, { from: alice })
            await spvdao.getProposal(1).then((res) => {
                expect(res.ended).to.eq(true)
            })
        })
        it("createReview", async () => {
            await spvdao.createProposal("test2", bob, web3.utils.toWei(new BN(100)), ido.address, 1, { from: alice })
            await spvdao.deposit(web3.utils.toWei(new BN(1000)), { from: alice })
            await spvdao.voteProposal(1, 2, 1, { from: alice })
            await timeTraveler.advanceTime(duration.days(40))
            let balance
            await ido.balanceOf(spvdao.address).then((res) => {
                balance = Number(res)
            })
            await spvdao.endProposalVote(2, { from: alice })
            await ido.balanceOf(spvdao.address).then((res) => {
                expect(balance).to.greaterThan(Number(res));
            })
            expect(Number(await spvdao.getReviewIds(2))).to.eq(0)
            expectEvent(await spvdao.createReview(2, "abc", { from: alice }), "NewReview")
            expect(Number(await spvdao.getReviewIds(2))).to.eq(1)
        })
        it("multipleVotes", async () => {
            await spvdao.createProposal("test3", bob, 100, ido.address, 1, { from: alice })
            await spvdao.createProposal("test4", bob, 100, ido.address, 1, { from: alice })
            await spvdao.voteProposal(1, 3, 1, { from: alice })
            await spvdao.getProposal(1).then((res) => {
                let votes = res.options.reduce((a, c) => a + Number(c.votes), 0)
                expect(votes).to.greaterThan(1)
            })
            await spvdao.voteProposal(1, 4, 1, { from: alice })
            await spvdao.getProposal(4).then((res) => {
                let votes = res.options.reduce((a, c) => a + Number(c.votes), 0)
                expect(votes).to.greaterThan(1)
            })
        })
        it("voteReview", async () => {
            await spvdao.getReview(2, 0).then((res) => {
                let reviews = res.options.reduce((a, c) => a + Number(c.votes), 0)
                expect(reviews).to.eq(0)
            })
            await spvdao.voteReview(1, 2, 0, 1, { from: alice })
            await spvdao.getReview(2, 0).then((res) => {
                let reviews = res.options.reduce((a, c) => a + Number(c.votes), 0)
                expect(reviews).to.greaterThan(1)
            })
        })
        it("endReviewVote", async () => {
            await spvdao.getReview(2, 0).then((res) => {
                expect(res.ended).to.eq(false)
            })
            await timeTraveler.advanceTime(duration.days(40))
            await spvdao.endReviewVote(2, 0, { from: alice })
            await spvdao.getReview(2, 0).then((res) => {
                expect(res.ended).to.eq(true)
            })
        })
        it("createComment", async () => {
            expect((await spvdao.getComments(2)).length).to.eq(0)
            expectEvent(await spvdao.createComment(1, 2, "test_comment", { from: alice }), "NewComment")
            expect((await spvdao.getComments(2)).length).to.eq(1)
        })
        after(async () => {
            await timeTraveler.advanceTime(time.duration.days(-120))
        })
    })
})
