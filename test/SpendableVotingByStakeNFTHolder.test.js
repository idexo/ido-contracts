const { ethers } = require("hardhat")

const { expect } = require("chai")
const { duration } = require("./helpers/time")
const { BN, constants, expectEvent, expectRevert, time } = require("@openzeppelin/test-helpers")
const { toWei } = require("web3-utils")
// const time = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")

async function deployContracts(paymentTokenAddress = undefined) {
    const [owner, alice, bob, carol, darren, payee] = await ethers.getSigners()
    console.log()

    // Deploy the necessary token contracts
    const ERC20Token = await ethers.getContractFactory("ERC20Mock")
    const erc20Token = await ERC20Token.deploy("ERC20 Token", "TKN")

    const NFT = await ethers.getContractFactory("StakePoolFlexLock")
    const nft = await NFT.deploy("NFT", "NFT", "", toWei("100"), erc20Token.address, erc20Token.address)

    const stakeTypes = await nft.addStakeTypes(["day", "week"], [1, 7])

    // If no payment token address is provided, use the ERC20 token address
    if (!paymentTokenAddress) {
        paymentTokenAddress = erc20Token.address
    }

    // Deploy the SpendableVotingByStakeNFTHolder contract
    const SpendableVotingByStakeNFTHolder = await ethers.getContractFactory("SpendableVotingByStakeNFTHolder")
    const spendableVoting = await SpendableVotingByStakeNFTHolder.deploy(14, 14, [nft.address])

    return { owner, alice, bob, carol, darren, payee, erc20Token, nft, spendableVoting }
}

describe("Run Tests", async () => {
    describe("SpendableVotingByStakeNFTHolder (ERC20)", function () {
        let owner, alice, bob, carol, darren, payee, erc20Token, nft, spendableVoting

        before(async function () {
            const setupData = await deployContracts()

            owner = setupData.owner
            alice = setupData.alice
            bob = setupData.bob
            carol = setupData.carol
            darren = setupData.darren
            payee = setupData.payee
            erc20Token = setupData.erc20Token
            nft = setupData.nft
            spendableVoting = setupData.spendableVoting

            const voters = [alice, bob, carol, darren]

            // Setup (e.g., mint NFT for voters, approve ERC20 tokens to the contract)
            for (const voter of voters) {
                await erc20Token.mint(voter.address, toWei("1000"))
                await erc20Token.connect(voter).approve(nft.address, toWei("1000"))
                await expect(nft.connect(voter).deposit(toWei("100"), "week", true)).to.emit(nft, "Deposited")
            }

            // mint tokens for the owner
            await erc20Token.mint(owner.address, toWei("100000"))
            await erc20Token.connect(owner).approve(spendableVoting.address, toWei("50000"))
        })

        describe("Fund contract", async () => {
            it("should deposit funds into the contract", async function () {
                // Deposit funds into the SpendableVoting contract
                await expect(spendableVoting.connect(owner).depositFunds(erc20Token.address, toWei("10000")))
                    .to.emit(spendableVoting, "FundDeposited")
                    .withArgs(owner.address, erc20Token.address, toWei("10000"))

                // check contract balance
                expect(await erc20Token.balanceOf(spendableVoting.address)).to.equal(toWei("10000"))
            })

            describe("Revert if", async () => {
                it("insufficient allowance", async () => {
                    await expect(spendableVoting.connect(owner).depositFunds(erc20Token.address, toWei("60000"))).to.be.revertedWith(
                        "INSUFFICIENT_ALLOWANCE"
                    )
                })

                it("insufficient balance", async () => {
                    await expect(spendableVoting.connect(owner).depositFunds(erc20Token.address, toWei("110000"))).to.be.revertedWith(
                        "INSUFFICIENT_BALANCE"
                    )
                })
            })
        })

        describe("Proposals", async () => {
            describe("prefund type", async () => {
                it("should create a proposal", async function () {
                    const proposer = alice
                    const amount = toWei("100")
                    const fundType = 0

                    // Create the proposal 1
                    await expect(
                        spendableVoting.connect(proposer).createProposal("Test Proposal 1", payee.address, amount, erc20Token.address, fundType)
                    )
                        .to.emit(spendableVoting, "NewProposal")
                        .withArgs(1, proposer.address)
                })

                it("should vote on a proposal", async function () {
                    // Get the proposal IDs
                    const proposal = await spendableVoting.getProposal(1)
                    // Vote
                    await spendableVoting.connect(alice).voteProposal(1, 1)
                })

                it("should end a proposal and transfer funds", async function () {
                    // Advance the time
                    await time.increase(time.duration.days(15))

                    // chack payee balance before
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(0)

                    // End the proposal
                    await spendableVoting.connect(alice).endProposalVote(1)

                    // // check payee balance after
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("100"))

                    // check contract balance after
                    expect(await erc20Token.balanceOf(spendableVoting.address)).to.equal(toWei("9900"))
                })
            })

            describe("half half type", async () => {
                it("should create a proposal", async function () {
                    const proposer = alice
                    const amount = toWei("100")
                    const fundType = 1

                    // Create the proposal 1
                    await expect(
                        spendableVoting.connect(proposer).createProposal("Test Proposal 2", payee.address, amount, erc20Token.address, fundType)
                    )
                        .to.emit(spendableVoting, "NewProposal")
                        .withArgs(2, proposer.address)
                })

                it("should vote on a proposal", async function () {
                    // Vote
                    await spendableVoting.connect(alice).voteProposal(2, 1)
                    await spendableVoting.connect(bob).voteProposal(2, 1)
                })

                it("should end a proposal and transfer funds", async function () {
                    // Advance the time
                    await time.increase(time.duration.days(15))

                    // chack payee balance before
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("100"))

                    // End the proposal
                    await spendableVoting.connect(alice).endProposalVote(2)

                    // // check payee balance after
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("150"))

                    // check contract balance after
                    expect(await erc20Token.balanceOf(spendableVoting.address)).to.equal(toWei("9850"))
                })
            })

             describe("postfund type", async () => {
                it("should create a proposal", async function () {
                    const proposer = alice
                    const amount = toWei("100")
                    const fundType = 2

                    // Create the proposal 2
                    await expect(
                        spendableVoting.connect(proposer).createProposal("Test Proposal 3", payee.address, amount, erc20Token.address, fundType)
                    )
                        .to.emit(spendableVoting, "NewProposal")
                        .withArgs(3, proposer.address)
                })

                it("should vote on a proposal", async function () {
                    // Vote
                    await spendableVoting.connect(alice).voteProposal(3, 1)
                    await spendableVoting.connect(bob).voteProposal(3, 1)
                })

                it("should end a proposal and don't transfer funds", async function () {
                    // Advance the time
                    await time.increase(time.duration.days(15))

                    // chack payee balance before
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("150"))

                    // End the proposal
                    await spendableVoting.connect(alice).endProposalVote(3)

                    // // check payee balance after
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("150"))

                    // check contract balance after
                    expect(await erc20Token.balanceOf(spendableVoting.address)).to.equal(toWei("9850"))
                })
            })

            describe("rejected proposal", async () => {
                it("should create a proposal", async function () {
                    // Create the proposal 1
                    await expect(spendableVoting.connect(alice).createProposal("Test Proposal 4", payee.address, toWei("200"), erc20Token.address, 1))
                        .to.emit(spendableVoting, "NewProposal")
                        .withArgs(4, alice.address)
                })

                it("should vote on a proposal", async function () {
                    // Vote
                    await spendableVoting.connect(alice).voteProposal(4, 1)
                    await spendableVoting.connect(bob).voteProposal(4, 2)
                    await spendableVoting.connect(carol).voteProposal(4, 2)
                    await spendableVoting.connect(darren).voteProposal(4, 2)
                })

                it("should end a proposal and don't transfer funds", async function () {
                    // Advance the time
                    await time.increase(time.duration.days(15))

                    // chack payee balance before
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("150"))

                    // End the proposal
                    await spendableVoting.connect(alice).endProposalVote(4)

                    // // check payee balance after
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("150"))

                    // check contract balance after
                    expect(await erc20Token.balanceOf(spendableVoting.address)).to.equal(toWei("9850"))
                })
            })

            // TODO: dup requirement lines 129/131 in SpendableVotingByStakeNFTHolder.sol

            describe("Reverts if", async () => {
                // create proposal for testing
                before(async function () {
                    // Create the proposal 2
                    await expect(spendableVoting.connect(alice).createProposal("Test Proposal 3", payee.address, toWei("100"), erc20Token.address, 1))
                        .to.emit(spendableVoting, "NewProposal")
                        .withArgs(5, alice.address)
                    await spendableVoting.connect(alice).voteProposal(5, 1)
                })

                it("proposal already ended", async function () {
                    await expectRevert(spendableVoting.connect(alice).endProposalVote(1), "ALREADY_ENDED")
                })

                it("proposal not ended", async function () {
                    await expectRevert(spendableVoting.connect(alice).endProposalVote(5), "OPEN_FOR_VOTE")
                })

                it("invalid proposal", async function () {
                    await expectRevert(spendableVoting.connect(alice).voteProposal(6, 1), "INVALID_PROPOSAL")
                })
                it("invalid option", async function () {
                    await expectRevert(spendableVoting.connect(bob).voteProposal(5, 4), "INVALID_OPTION")
                })
                it("already voted", async function () {
                    await expectRevert(spendableVoting.connect(alice).voteProposal(5, 1), "ALREADY_VOTED")
                })
                it("voter not NFT holder", async function () {
                    await expectRevert(spendableVoting.connect(owner).voteProposal(5, 1), "NOT_NFT_HOLDER")
                })
                it("proposer not NFT holder", async function () {
                    await expectRevert(
                        spendableVoting.connect(owner).createProposal("Test Proposal Failed", payee.address, toWei("100"), erc20Token.address, 1),
                        "NOT_NFT_HOLDER"
                    )
                })
                it("invalid Fund Type", async function () {
                    await expectRevert(
                        spendableVoting.connect(alice).createProposal("Test Proposal Failed", payee.address, toWei("100"), erc20Token.address, 4),
                        "INVALID_FUND_TYPE"
                    )
                })
                it("invalid amount", async function () {
                    await expectRevert(
                        spendableVoting.connect(alice).createProposal("Test Proposal Failed", payee.address, toWei("0"), erc20Token.address, 1),
                        "AMOUNT_MUST_BE_GREATER_THAN_ZERO"
                    )
                })
                it("insufficient funds on contract", async function () {
                    await expectRevert(
                        spendableVoting.connect(alice).createProposal("Test Proposal Failed", payee.address, toWei("15000"), erc20Token.address, 1),
                        "INSUFFICIENT_FUNDS"
                    )
                })
                it("paymentToken not contract", async function () {
                    await expectRevert(
                        spendableVoting.connect(alice).createProposal("Test Proposal Failed", payee.address, toWei("0"), bob.address, 1),
                        "NOT_CONTRACT"
                    )
                })
            })
        })

        describe("Comments", async () => {
            it("should comment a proposal", async () => {
                await expect(spendableVoting.connect(alice).createComment(1, "Test Comment"))
                    .to.emit(spendableVoting, "NewComment")
                    .withArgs(alice.address, 1, 1, "Test Comment")
            })

            it("get comments", async () => {
                const comments = await spendableVoting.getComments(1)
                expect(comments.length).to.equal(1)
                expect(comments[0].commentURI).to.equal("Test Comment")
            })

            describe("Reverts if", async () => {
                it("not proposal voter", async () => {
                    await expectRevert(spendableVoting.connect(bob).createComment(1, "Test Comment"), "NOT_PROPOSAL_VOTER")
                })
            })
        })

        describe("Reviews", async () => {
            describe("prefund type", async () => {
                it("shoud create a review", async () => {
                    // Create the proposal 1
                    await expect(spendableVoting.connect(alice).createProposal("Test Proposal 5", payee.address, toWei("100"), erc20Token.address, 1))
                        .to.emit(spendableVoting, "NewProposal")
                        .withArgs(6, alice.address)
                    await spendableVoting.connect(alice).voteProposal(6, 1)
                    await spendableVoting.connect(bob).voteProposal(6, 2)
                    await spendableVoting.connect(carol).voteProposal(6, 2)
                    await spendableVoting.connect(darren).voteProposal(6, 2)

                    // get reviewIds
                    const reviewIds = await spendableVoting.getReviewIds(1)
                    // get review
                    if (reviewIds > 0) {
                        const review = await spendableVoting.getReview(1, reviewIds - 1) // get last review
                        expect(review.description).to.equal("Test Review for Proposal 1")
                    }
                })
            })

            describe("half half type", async () => {
                it("should create a review", async function () {
                    // Create the proposal 1
                    await expect(spendableVoting.connect(alice).createReview(2, "Test Review for Proposal 2"))
                        .to.emit(spendableVoting, "NewReview")
                        .withArgs(2, 1)

                    // get reviewIds
                    const reviewIds = await spendableVoting.getReviewIds(2)
                    // get review
                    if (reviewIds > 0) {
                        const review = await spendableVoting.getReview(2, reviewIds - 1) // get last review
                        expect(review.description).to.equal("Test Review for Proposal 2")
                    }
                })

                it("should vote on a review", async function () {
                    // Vote
                    await spendableVoting.connect(alice).voteReview(2, 0, 1)
                    await spendableVoting.connect(bob).voteReview(2, 0, 1)
                })

                it("should end a review and transfer funds", async function () {
                    // Advance the time
                    await time.increase(time.duration.days(15))

                    // chack payee balance before
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("150"))

                    // End the proposal
                    await spendableVoting.connect(alice).endReviewVote(2, 0)

                    // // check payee balance after
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("200"))

                    // check contract balance after
                    expect(await erc20Token.balanceOf(spendableVoting.address)).to.equal(toWei("9800"))
                })
                })

                describe("postfund type", async () => {
                it("should create a review", async function () {
                    // Create the proposal 1
                    await expect(spendableVoting.connect(alice).createReview(3, "Test Review for Proposal 3"))
                        .to.emit(spendableVoting, "NewReview")
                        .withArgs(3, 1)

                    // get reviewIds
                    const reviewIds = await spendableVoting.getReviewIds(3)
                    // get review
                    if (reviewIds > 0) {
                        const review = await spendableVoting.getReview(3, reviewIds - 1) // get last review
                        expect(review.description).to.equal("Test Review for Proposal 3")
                    }
                })

                it("should vote on a review", async function () {
                    // Vote
                    await spendableVoting.connect(alice).voteReview(3, 0, 1)
                    await spendableVoting.connect(bob).voteReview(3, 0, 1)
                })

                it("should end a review and transfer funds", async function () {
                    // Advance the time
                    await time.increase(time.duration.days(15))

                    // chack payee balance before
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("200"))

                    // End the proposal
                    await spendableVoting.connect(alice).endReviewVote(3, 0)

                    // // check payee balance after
                    expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("300"))

                    // check contract balance after
                    expect(await erc20Token.balanceOf(spendableVoting.address)).to.equal(toWei("9700"))
                })

                // test create another review
                // it("should create a review", async function () {
                //     // Create the proposal 1
                //     await expect(spendableVoting.connect(alice).createReview(2, "Test Review 2 for Proposal 2"))
                //         .to.emit(spendableVoting, "NewReview")
                //         .withArgs(2, 2)

                //     // get reviewIds
                //     const reviewIds = await spendableVoting.getReviewIds(2)
                //     // get review
                //     if (reviewIds > 0) {
                //         const review = await spendableVoting.getReview(2, reviewIds - 1) // get last review
                //         expect(review.description).to.equal("Test Review 2 for Proposal 2")
                //     }
                // })

                // it("should vote on a review 2", async function () {
                //     // Vote
                //     await spendableVoting.connect(alice).voteReview(2, 1, 1)
                //     await spendableVoting.connect(bob).voteReview(2, 1, 1)
                // })

                // it("should end a review and transfer funds", async function () {
                //     // Advance the time
                //     await time.increase(time.duration.days(15))

                //     // chack payee balance before
                //     expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("150"))

                //     // End the proposal
                //     await spendableVoting.connect(alice).endReviewVote(2, 1)

                //     // // check payee balance after
                //     expect(await erc20Token.balanceOf(payee.address)).to.equal(toWei("200"))

                //     // check contract balance after
                //     expect(await erc20Token.balanceOf(spendableVoting.address)).to.equal(toWei("9800"))
                // })
            })

            describe("Reverts if", async () => {
                // create proposal for testing
                before(async function () {
                    // Create and reject a proposal
                    await expect(spendableVoting.connect(alice).createProposal("Test Proposal 7", payee.address, toWei("100"), erc20Token.address, 1))
                        .to.emit(spendableVoting, "NewProposal")
                        .withArgs(7, alice.address)
                    await spendableVoting.connect(alice).voteProposal(7, 1)
                    await spendableVoting.connect(bob).voteProposal(7, 2)
                    await spendableVoting.connect(carol).voteProposal(7, 2)
                    await spendableVoting.connect(darren).voteProposal(7, 2)
                })

                it("not owner or author", async function () {
                    await expectRevert(spendableVoting.connect(darren).createReview(7, "Failed Review"), "NOT_OWNER_OR_AUTHOR")
                })

                it("open for vote", async function () {
                    await expectRevert(spendableVoting.connect(alice).createReview(7, "Failed Review"), "PROPOSAL_VOTE_OPEN")
                })

                it("rejected proposal", async function () {
                    await time.increase(time.duration.days(15))
                    await spendableVoting.connect(alice).endProposalVote(7)
                    await expectRevert(spendableVoting.connect(alice).createReview(7, "Failed Review"), "REJECTED_PROPOSAL")
                })
            })
        })

        
    })

    describe("SpendableVotingByStakeNFTHolder (ETH)", function () {
        let owner, alice, bob, carol, darren, payee, erc20Token, nft, spendableVoting

        before(async function () {
            const setupData = await deployContracts(constants.ZERO_ADDRESS)

            owner = setupData.owner
            alice = setupData.alice
            bob = setupData.bob
            carol = setupData.carol
            darren = setupData.darren
            payee = setupData.payee
            erc20Token = setupData.erc20Token
            nft = setupData.nft
            spendableVoting = setupData.spendableVoting

            const voters = [alice, bob, carol, darren]

            // Setup (e.g., mint NFT for voters, approve ERC20 tokens to the contract)
            for (const voter of voters) {
                await erc20Token.mint(voter.address, toWei("1000"))
                await erc20Token.connect(voter).approve(nft.address, toWei("1000"))
                await expect(nft.connect(voter).deposit(toWei("100"), "week", true)).to.emit(nft, "Deposited")

                // check voter balance
                expect(await erc20Token.balanceOf(voter.address)).to.equal(toWei("900"))
                // check nft balance
                expect(await nft.balanceOf(voter.address)).to.equal(1)
            }
        })

        describe("Fund contract", async () => {
            it("should deposit ETH funds into the contract", async function () {
                // Deposit funds into the SpendableVoting contract
                await spendableVoting.connect(owner).depositFundsEth({ value: toWei("200") })

                // check contract balance
                expect(await ethers.provider.getBalance(spendableVoting.address)).to.equal(toWei("200"))
            })

            describe("Revert if", async () => {
                it("zero amount", async () => {
                    await expect(spendableVoting.connect(owner).depositFundsEth({ value: toWei("0") })).to.be.revertedWith("ZERO_AMOUNT")
                })
            })
        })

        describe("Proposals", async () => {
            describe("prefund type", async () => {
                it("should create a proposal", async function () {
                    // Create the proposal 1
                    await expect(
                        spendableVoting.connect(alice).createProposal("Test Proposal 1", payee.address, toWei("100"), constants.ZERO_ADDRESS, 0)
                    )
                        .to.emit(spendableVoting, "NewProposal")
                        .withArgs(1, alice.address)
                })

                it("should vote on a proposal", async function () {
                    // Get the proposal IDs
                    const proposal = await spendableVoting.getProposal(1)
                    // Vote
                    await spendableVoting.connect(alice).voteProposal(1, 1)
                })

                it("should end a proposal and transfer funds", async function () {
                    // Advance the time
                    await time.increase(time.duration.days(15))

                    // chack payee eth balance before
                    // console.log("payee eth balance before", await ethers.provider.getBalance(payee.address))
                    // expect((await ethers.provider.getBalance(payee.address)).toString()).to.equal(toWei("10000"))

                    const balanceBefore = await ethers.provider.getBalance(payee.address)

                    // End the proposal
                    await spendableVoting.connect(alice).endProposalVote(1)

                    // // check payee eth balance after
                    // console.log("payee eth balance after", await ethers.provider.getBalance(payee.address))
                    expect((await ethers.provider.getBalance(payee.address)).sub(balanceBefore)).to.equal(toWei("100"))

                    // check contract eth balance after
                    expect(await ethers.provider.getBalance(spendableVoting.address)).to.equal(toWei("100"))
                })
            })

            describe("half half type", async () => {
                it("should create a proposal", async function () {
                    // Create the proposal 2
                    await expect(
                        spendableVoting.connect(alice).createProposal("Test Proposal 2", payee.address, toWei("100"), constants.ZERO_ADDRESS, 1)
                    )
                        .to.emit(spendableVoting, "NewProposal")
                        .withArgs(2, alice.address)
                })

                it("should vote on a proposal", async function () {
                    // Vote
                    await spendableVoting.connect(alice).voteProposal(2, 1)
                    await spendableVoting.connect(bob).voteProposal(2, 1)
                })

                it("should end a proposal and transfer funds", async function () {
                    // Advance the time
                    await time.increase(time.duration.days(15))

                    // chack payee balance before
                    const balanceBefore = await ethers.provider.getBalance(payee.address)

                    // End the proposal
                    await spendableVoting.connect(alice).endProposalVote(2)

                    // // check payee eth balance after
                    expect((await ethers.provider.getBalance(payee.address)).sub(balanceBefore)).to.equal(toWei("50"))

                    // check contract eth balance after
                    expect(await ethers.provider.getBalance(spendableVoting.address)).to.equal(toWei("50"))
                })
            })
        })

        describe("Reviews", async () => {
            describe("half half type", async () => {
                it("should create a review", async function () {
                    // Create the review 1
                    await expect(spendableVoting.connect(alice).createReview(2, "Test Review for Proposal 2"))
                        .to.emit(spendableVoting, "NewReview")
                        .withArgs(2, 1)

                    // get reviewIds
                    const reviewIds = await spendableVoting.getReviewIds(2)
                    // get review
                    if (reviewIds > 0) {
                        const review = await spendableVoting.getReview(2, reviewIds - 1) // get last review
                        expect(review.description).to.equal("Test Review for Proposal 2")
                    }
                })

                it("should vote on a review", async function () {
                    // Vote
                    await spendableVoting.connect(alice).voteReview(2, 0, 1)
                    await spendableVoting.connect(bob).voteReview(2, 0, 1)
                })

                it("should end a review and transfer funds", async function () {
                    // Advance the time
                    await time.increase(time.duration.days(15))

                    // chack payee balance before
                    const balanceBefore = await ethers.provider.getBalance(payee.address)

                    // End the proposal
                    await spendableVoting.connect(alice).endReviewVote(2, 0)

                    // // check payee eth balance after
                    expect((await ethers.provider.getBalance(payee.address)).sub(balanceBefore)).to.equal(toWei("50"))

                    // check contract balance after
                    expect(await ethers.provider.getBalance(spendableVoting.address)).to.equal(toWei("0"))
                })
            })
        })

        
    })
})
