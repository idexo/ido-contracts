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
    let ido, usdt
    let voting, sPool1, sPool2, sPool3, sPool4
    const [alice, bob, carol] = accounts

    before(async () => {
        ido = await ERC20.new("Idexo Community", "IDO", { from: alice })
        usdt = await ERC20.new("USD Tether", "USDT", { from: alice })
        sPool1 = await StakePool.new("Idexo Stake Token", "IDS", "", ido.address, usdt.address)
        sPool2 = await StakePool.new("Idexo Stake Token", "IDS", "", ido.address, usdt.address)
        sPool3 = await StakePool.new("Idexo Stake Token", "IDS", "", ido.address, usdt.address)
        sPool4 = await StakePool.new("Idexo Stake Token", "IDS", "", ido.address, usdt.address)
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

    describe("#Fund Accounts", async () => {
        it("should fund accounts with usdt", async () => {
            await usdt.mint(alice, web3.utils.toWei(new BN(5000)))
            await usdt.mint(bob, web3.utils.toWei(new BN(5000)))
        })
    })

    describe("#Mock Stakes", async () => {
        before(async () => {
            await ido.mint(alice, web3.utils.toWei(new BN(200000)))
            await ido.approve(sPool1.address, web3.utils.toWei(new BN(200000)), { from: alice })
            await ido.mint(bob, web3.utils.toWei(new BN(200000)))
            await ido.approve(sPool2.address, web3.utils.toWei(new BN(200000)), { from: bob })
            await ido.mint(carol, web3.utils.toWei(new BN(200000)))
            await ido.approve(sPool1.address, web3.utils.toWei(new BN(200000)), { from: carol })
        })
        describe("##stakes", async () => {
            it("should create mock stakes", async () => {
                await sPool1.deposit(web3.utils.toWei(new BN(5200)), { from: alice })
                await sPool1.getStakeInfo(1).then((res) => {
                    expect(res[0].toString()).to.eq("5200000000000000000000")
                })
                await sPool2.deposit(web3.utils.toWei(new BN(5200)), { from: bob })
                await sPool2.getStakeInfo(1).then((res) => {
                    expect(res[0].toString()).to.eq("5200000000000000000000")
                })
                const aliceIDOBalance = await ido.balanceOf(alice)
                expect(aliceIDOBalance.toString()).to.eq("194800000000000000000000")
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

    describe("#Proposal", async () => {
        // TODO: checking payeeWallet
        describe("reverts if", async () => {
            it("INSUFFICIENT_FUNDS", async () => {
                await expectRevert(
                    voting.createProposal("Test Proposal 1", alice, web3.utils.toWei(new BN(1)), usdt.address, 1, { from: alice }),
                    "INSUFFICIENT_FUNDS"
                )
            })
        })

        describe("#Deposit Funds", async () => {
            it("should deposit funds to this voting contract", async () => {
                await usdt.balanceOf(alice).then((balance) => {
                    expect(balance.toString()).to.eq(web3.utils.toWei(new BN(5000)).toString())
                })
                await usdt.approve(voting.address, web3.utils.toWei(new BN(5000)), { from: alice })
                await voting.depositFunds(usdt.address, web3.utils.toWei(new BN(5000)), { from: alice })

                await usdt.balanceOf(voting.address).then((balance) => {
                    expect(balance.toString()).to.eq(web3.utils.toWei(new BN(5000)).toString())
                })
            })

            describe("reverts if", async () => {
                it("INSUFFICIENT_BALANCE", async () => {
                    await expectRevert(voting.depositFunds(usdt.address, web3.utils.toWei(new BN(5000)), { from: alice }), "INSUFFICIENT_BALANCE")
                })
                it("INSUFFICIENT_ALLOWANCE", async () => {
                    await expectRevert(voting.depositFunds(usdt.address, web3.utils.toWei(new BN(5000)), { from: bob }), "INSUFFICIENT_ALLOWANCE")
                })
            })
        })

        describe("#Create proposal", async () => {
            it("create new proposal", async () => {
                voting.createProposal("Test Proposal 1", alice, web3.utils.toWei(new BN(1)), usdt.address, 1, { from: alice })
            })
        })

        describe("#Get proposal", async () => {
            it("should get proposal #1", async () => {
                const proposal = await voting.getProposal(1)
                // console.log(proposal)
            })
        })

        describe("#Vote proposal", async () => {
            it("should vote proposal #1", async () => {
                await voting.voteProposal(1, 1, { from: alice })
                const proposal = await voting.getProposal(1)
                await voting.getProposal(1).then((proposal) => {
                    expect(proposal.options[0]["votes"]).to.eq("1")
                })
            })

            describe("reverts if", async () => {
                it("ALREADY_VOTED", async () => {
                    await expectRevert(voting.voteProposal(1, 1, { from: alice }), "ALREADY_VOTED")
                })
                it("NOT_NFT_HOLDER", async () => {
                    await expectRevert(voting.voteProposal(1, 1, { from: carol }), "NOT_NFT_HOLDER")
                })
                it("INVALID_OPTION", async () => {
                    await expectRevert(voting.voteProposal(1, 5, { from: bob }), "INVALID_OPTION")
                })
            })
        })

        describe("#Comments", async () => {
            it("create new proposal comment", async () => {
                voting.createComment(1, "The contract expects a URi for the comment", { from: alice })
            })

            describe("get comments", async () => {
                it("should get comments", async () => {
                    await voting.getComments(1).then((comments) => {
                        expect(comments[0]["author"]).to.eq(alice)
                        expect(comments[0]["commentURI"]).to.eq("The contract expects a URi for the comment")
                    })
                })
            })

            describe("reverts if", async () => {
                it("NOT_PROPOSAL_VOTER", async () => {
                    await expectRevert(voting.createComment(1, "The contract expects a URi for the comment", { from: carol }), "NOT_PROPOSAL_VOTER")
                })
            })
        })

        describe("#Review", async () => {
            describe("reverts if", async () => {
                it("NOT_OWNER_OR_AUTHOR", async () => {
                    await expectRevert(voting.createReview(1, "try creating review with no propopsal owner", { from: bob }), "NOT_OWNER_OR_AUTHOR")
                })
                it("NOT_NFT_HOLDER", async () => {
                    await sPool1.transferFrom(alice, bob, 1, { from: alice })
                    await expectRevert(voting.createReview(1, "First proposal id #1 review", { from: alice }), "NOT_NFT_HOLDER")
                })
                it("PROPOSAL_VOTE_OPEN", async () => {
                    await sPool1.transferFrom(bob, alice, 1, { from: bob })
                    await expectRevert(voting.createReview(1, "First proposal id #1 review", { from: alice }), "PROPOSAL_VOTE_OPEN")
                })
                // it("REJECTED_PROPOSAL", async () => {
                //     await expectRevert(voting.voteProposal(1, 5, { from: bob }), "REJECTED_PROPOSAL")
                // })
            })

            // it("should create review", async () => {
            //     await voting.createReview(1, "First proposal id #1 review", { from: alice })
            // })
        })
    })

    describe("#Sweep", async () => {
        it("should sweep funds from contract", async () => {
            voting.sweep(usdt.address, carol, web3.utils.toWei(new BN(5000)))
        })
    })
})
