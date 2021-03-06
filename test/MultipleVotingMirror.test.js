const MultipleVotingMirror = artifacts.require("MultipleVotingMirror")
const StakeMirrorNFT = artifacts.require("contracts/staking/StakeMirrorNFT.sol:StakeMirrorNFT")
const ERC20 = artifacts.require("ERC20Mock")

const { expect } = require("chai")
const { BN, constants, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const { toWei } = require("web3-utils")
const time = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")

contract("MultipleVotingMirror", async (accounts) => {
    let voting, sPool1, sPool2, sPool3, sPool4
    const [alice, bob, carol] = accounts

    before(async () => {
        sPool1 = await StakeMirrorNFT.new("IGSP Mirror", "IGSPM", "https://idexo.io/metadata/")
        sPool2 = await StakeMirrorNFT.new("IGSP Mirror", "IGSPM", "https://idexo.io/metadata/")
        sPool3 = await StakeMirrorNFT.new("IGSP Mirror", "IGSPM", "https://idexo.io/metadata/")
        sPool4 = await StakeMirrorNFT.new("IGSP Mirror", "IGSPM", "https://idexo.io/metadata/")
        voting = await MultipleVotingMirror.new([sPool1.address, sPool2.address])
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
                await expectRevert(voting.addOperator(bob, { from: bob }), "CALLER_NO_ADMIN_ROLE")
            })
            it("remove operator by non-admin", async () => {
                await voting.addOperator(bob)
                await expectRevert(voting.removeOperator(bob, { from: bob }), "CALLER_NO_ADMIN_ROLE")
            })
        })
    })

    describe("#StakeMirrorNFT", async () => {
        it("addStakePool", async () => {
            await voting.addStakePool(sPool3.address, { from: bob })
            expect(await voting.isStakePool(sPool1.address)).to.eq(true)
            expect(await voting.isStakePool(sPool2.address)).to.eq(true)
            expect(await voting.isStakePool(sPool3.address)).to.eq(true)
        })
        it("supportsInterface", async () => {
            await sPool1.supportsInterface("0x00").then((res) => {
                expect(res).to.eq(false)
            })
        })
        it("addOperator removeOperator", async () => {
            await sPool1.addOperator(bob)
            expect(await sPool1.checkOperator(bob)).to.eq(true)
            await sPool1.removeOperator(bob)
            expect(await sPool1.checkOperator(bob)).to.eq(false)
        })
        it("set baseURI", async () => {
            await sPool1.setBaseURI("https://newBaseURI/")
            expect(await sPool1.baseURI()).to.eq("https://newBaseURI/")
            await sPool1.setBaseURI("https://idexo.io/metadata/")
        })
        it("getStakeAmount isHolder setTokenURI tokenURI decreaseStakeAmount", async () => {
            await sPool1.getStakeAmount(bob).then((res) => {
                expect(res.words[0]).to.eq(0)
            })
            await sPool1.mint(bob, 1, toWei(new BN(4000)), 120, 1632842216)
            expect(await sPool1.isHolder(bob)).to.eq(true)
            await sPool1.setTokenURI(1, "test")
            expect(await sPool1.tokenURI(1)).to.eq("https://idexo.io/metadata/test")
            expectEvent(await sPool1.decreaseStakeAmount(1, toWei(new BN(2000))), "StakeAmountDecreased")
            await sPool1.decreaseStakeAmount(1, toWei(new BN(2000)))
            await sPool1.getStakeAmount(bob).then((res) => {
                expect(res.words[0]).to.eq(0)
            })
        })
        it("removeStakePool", async () => {
            await voting.addStakePool(sPool4.address, { from: bob })
            await voting.removeStakePool(sPool3.address, { from: bob })
            expect(await voting.isStakePool(sPool3.address)).to.eq(false)
            expect(await voting.isStakePool(sPool4.address)).to.eq(true)
            await voting.removeStakePool(sPool4.address, { from: bob })
            expect(await voting.isStakePool(sPool4.address)).to.eq(false)
        })
        describe("multiples mint and burn", async () => {
            it("should stakes", async () => {
                await sPool1.mint(bob, 1, toWei(new BN(4000)), 120, 1632842216)
                await sPool1.mint(bob, 2, toWei(new BN(4000)), 120, 1632842216)
                await sPool1.mint(bob, 3, toWei(new BN(4000)), 120, 1632842216)

                await sPool1.getStakeAmount(bob).then((res) => {
                    expect(res.toString()).to.eq("12000000000000000000000")
                })

                await sPool1.decreaseStakeAmount(1, toWei(new BN(4000)))
                await sPool1.decreaseStakeAmount(2, toWei(new BN(4000)))
                await sPool1.decreaseStakeAmount(3, toWei(new BN(4000)))
            })
        })
        describe("reverts if", async () => {
            it("addStakePool removeStakePool", async () => {
                await expectRevert(voting.addStakePool(sPool3.address, { from: carol }), "CALLER_NO_OPERATOR_ROLE")
                await expectRevert(voting.addStakePool(constants.ZERO_ADDRESS, { from: bob }), "STAKE_POOL_ADDRESS_INVALID")
                await expectRevert(voting.addStakePool(sPool2.address, { from: bob }), "STAKE_POOL_ADDRESS_ALREADY_FOUND")
            })
        })
    })

    describe("#Poll", async () => {
        before(async () => {
            const latestBlock = await hre.ethers.provider.getBlock("latest")
            await sPool1.mint(alice, 1, toWei(new BN(4000)), 120, latestBlock.timestamp)
            await sPool1.mint(bob, 2, toWei(new BN(7000)), 120, latestBlock.timestamp - time.duration.days(90))
            
            // await sPool2.mint(alice, 1, toWei(new BN(8000)), 120, latestBlock.timestamp)
            // await sPool2.mint(bob, 2, toWei(new BN(14000)), 120, latestBlock.timestamp)
        })
        it("createPoll castVote getWeight", async () => {
            // create and start poll
            const latestBlock = await hre.ethers.provider.getBlock("latest")
            const startTime = latestBlock.timestamp + time.duration.days(10)
            const endTime = startTime + time.duration.days(80)
            // non-operator can not create the poll
            await expectRevert(
                voting.createPoll("Which network is next target?", ["Solana", "Tezos", "Cardano"], startTime, endTime, 0, { from: carol }),
                "CALLER_NO_OPERATOR_ROLE"
            )
            // poll description must not be empty
            await expectRevert(voting.createPoll("", ["Solana", "Tezos", "Cardano"], startTime, endTime, 0, { from: bob }), "DESCRIPTION_INVALID")
            // startTime and endTime must not be same
            await expectRevert(
                voting.createPoll("Which network is next target?", ["Solana", "Tezos", "Cardano"], startTime, startTime, 0, { from: bob }),
                "END_TIME_INVALID"
            )
            // operator can create
            await voting.createPoll("Which network is next target?", ["Solana", "Tezos", "Cardano"], startTime, endTime, 100, { from: bob })
            // returns general poll info, anybody can call anytime
            await voting.getPollInfo(1).then((res) => {
                expect(res[0]).to.eq("Which network is next target?")
                expect(res[1].length).to.eq(4)
                expect(res[3].sub(res[2]).toString()).to.eq(time.duration.days(80).toString())
                expect(res[4].toString()).to.eq("100")
                expect(res[5]).to.eq(bob)
            })
        })
        describe("reverts if", async () => {
            it("voting before minimum stake time", async () => {
                await expectRevert(voting.castVote(1, 1, { from: alice }), "STAKE_NOT_OLD_ENOUGH")
            })
        })
        describe("check", async () => {
            it("checkIfVoted endPoll", async () => {
                const newEndTime = Math.floor(Date.now() / 1000) + time.duration.days(115)
                expect(await voting.checkIfVoted(1, bob)).to.eq(false)
                expectEvent(await voting.castVote(1, 1, { from: bob }), "VoteCasted")
                expect(await voting.checkIfVoted(1, bob)).to.eq(true)
                // zero weight stakers can not cast vote
                await expectRevert(voting.castVote(1, 1, { from: carol }), "NO_VALID_VOTING_NFTS_PRESENT")
                await voting.updatePollTime(1, 0, newEndTime, { from: bob })
                //add one more staker
                const latestBlock = await hre.ethers.provider.getBlock("latest")
                await sPool1.mint(carol, 3, toWei(new BN(10000)), 120, latestBlock.timestamp - time.duration.days(91))
                expect(await voting.checkIfVoted(1, carol)).to.eq(false)
                expectEvent(await voting.castVote(1, 2, { from: carol}), "VoteCasted")
                expect(await voting.checkIfVoted(1, carol)).to.eq(true)
                // poll is still on
                // operators only can call
                await voting.getPollVotingInfo(1, { from: bob }).then((res) => {
                    expect(res[0][0].toString()).to.eq("0")
                    expect(res[0][1].toString()).to.eq("7000000000000000000000")
                    expect(res[0][2].toString()).to.eq("10000000000000000000000")
                    expect(res[0][3].toString()).to.eq("0")
                    expect(res[1].toString()).to.eq("2")
                })
                // non-operator can not call
                await expectRevert(voting.getPollVotingInfo(1, { from: carol }), "POLL_NOT_ENDED__CALLER_NO_OPERATOR")
                // operators only can call
                await voting.getVoterInfo(1, carol, { from: bob }).then((res) => {
                    expect(res[0].toString()).to.eq("2")
                    expect(res[1].toString()).to.eq("10000000000000000000000")
                })
                // non-operator can not call
                await expectRevert(voting.getVoterInfo(1, alice, { from: carol }), "POLL_NOT_ENDED__CALLER_NO_OPERATOR")
                await timeTraveler.advanceTimeAndBlock(time.duration.days(200))
                // poll ended, anybody can call
                await voting.getPollVotingInfo(1, { from: carol }).then((res) => {
                    expect(res[0][0].toString()).to.eq("0")
                    expect(res[0][1].toString()).to.eq("7000000000000000000000")
                    expect(res[0][2].toString()).to.eq("10000000000000000000000")
                    expect(res[0][3].toString()).to.eq("0")
                    expect(res[1].toString()).to.eq("2")
                })
                await voting.getVoterInfo(1, bob, { from: carol }).then((res) => {
                    expect(res[0].toString()).to.eq("1")
                    expect(res[1].toString()).to.eq("7000000000000000000000")
                })
                await timeTraveler.advanceTimeAndBlock(time.duration.days(-200))
            })
            it("updatePollTime", async () => {
                const number = await ethers.provider.getBlockNumber()
                const block = await ethers.provider.getBlock(number)
                await voting.createPoll("test?", ["y", "n"], block.timestamp + 1111, block.timestamp + 8888, 0, { from: bob })
                const pollId = Number(await voting.pollIds())
                const pollInfo1 = await voting.getPollInfo(pollId)
                await voting.updatePollTime(pollId, block.timestamp + 8888, block.timestamp + 9999, { from: bob })
                const pollInfo2 = await voting.getPollInfo(pollId)
                expect(Number(pollInfo1[2])).not.eq(Number(pollInfo2[2]))
                expect(Number(pollInfo1[3])).not.eq(Number(pollInfo2[3]))
            })
        })
    })
})
