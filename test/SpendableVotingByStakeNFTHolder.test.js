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
                const fundType = 1

                // Create the proposal 1
                await expect(spendableVoting.connect(proposer).createProposal("Test Proposal 1", payee.address, amount, erc20Token.address, fundType))
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
                const fundType = 2

                // Create the proposal 1
                await expect(spendableVoting.connect(proposer).createProposal("Test Proposal 2", payee.address, amount, erc20Token.address, fundType))
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

        describe("rejected proposal", async () => {
            it("should create a proposal", async function () {
                // Create the proposal 1
                await expect(spendableVoting.connect(alice).createProposal("Test Proposal 3", payee.address, toWei("200"), erc20Token.address, 1))
                    .to.emit(spendableVoting, "NewProposal")
                    .withArgs(3, alice.address)
            })

            it("should vote on a proposal", async function () {
                // Vote
                await spendableVoting.connect(alice).voteProposal(3, 1)
                await spendableVoting.connect(bob).voteProposal(3, 2)
                await spendableVoting.connect(carol).voteProposal(3, 2)
                await spendableVoting.connect(darren).voteProposal(3, 2)
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

        // TODO: dup requirement lines 129/131 in SpendableVotingByStakeNFTHolder.sol

        describe("Reverts if", async () => {
            // create proposal for testing
            before(async function () {
                // Create the proposal 2
                await expect(spendableVoting.connect(alice).createProposal("Test Proposal 3", payee.address, toWei("100"), erc20Token.address, 1))
                    .to.emit(spendableVoting, "NewProposal")
                    .withArgs(4, alice.address)
                await spendableVoting.connect(alice).voteProposal(4, 1)
            })

            it("proposal already ended", async function () {
                await expectRevert(spendableVoting.connect(alice).endProposalVote(1), "ALREADY_ENDED")
            })

            it("proposal not ended", async function () {
                await expectRevert(spendableVoting.connect(alice).endProposalVote(4), "OPEN_FOR_VOTE")
            })

            it("invalid proposal", async function () {
                await expectRevert(spendableVoting.connect(alice).voteProposal(5, 1), "INVALID_PROPOSAL")
            })
            it("invalid option", async function () {
                await expectRevert(spendableVoting.connect(bob).voteProposal(4, 4), "INVALID_OPTION")
            })
            it("already voted", async function () {
                await expectRevert(spendableVoting.connect(alice).voteProposal(4, 1), "ALREADY_VOTED")
            })
            it("voter not NFT holder", async function () {
                await expectRevert(spendableVoting.connect(owner).voteProposal(4, 1), "NOT_NFT_HOLDER")
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

        describe("Reverts if", async () => {
            // create proposal for testing
            before(async function () {
                // Create and reject a proposal
                await expect(spendableVoting.connect(alice).createProposal("Test Proposal 4", payee.address, toWei("100"), erc20Token.address, 1))
                    .to.emit(spendableVoting, "NewProposal")
                    .withArgs(5, alice.address)
                await spendableVoting.connect(alice).voteProposal(5, 1)
                await spendableVoting.connect(bob).voteProposal(5, 2)
                await spendableVoting.connect(carol).voteProposal(5, 2)
                await spendableVoting.connect(darren).voteProposal(5, 2)
            })

            it("not owner or author", async function () {
                await expectRevert(spendableVoting.connect(darren).createReview(5, "Failed Review"), "NOT_OWNER_OR_AUTHOR")
            })

            it("open for vote", async function () {
                await expectRevert(spendableVoting.connect(alice).createReview(5, "Failed Review"), "PROPOSAL_VOTE_OPEN")
            })

            it("rejected proposal", async function () {
                await time.increase(time.duration.days(15))
                await spendableVoting.connect(alice).endProposalVote(5)
                await expectRevert(spendableVoting.connect(alice).createReview(5, "Failed Review"), "REJECTED_PROPOSAL")
            })
        })
    })

    describe("sweep funds", async () => {
        it("should sweep funds", async () => {
            // get contract balance
            const contractBalance = await erc20Token.balanceOf(spendableVoting.address)

            // sweep funds
            await spendableVoting.connect(owner).sweep(erc20Token.address, owner.address, contractBalance.toString())

            // check if contract balance is 0
            expect(await erc20Token.balanceOf(spendableVoting.address)).to.equal(0)
        })
    })
})

// describe("SpendableVotingByStakeNFTHolder (ETH)", function () {
//     // ...
//     it("should create a proposal with Ethereum as payment token", async function () {
//         const [_, voter, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter.address, 1000)
//         await erc20Token.connect(voter).approve(nft.address, 1000)
//         await nft.connect(voter).deposit(100, "week", true)

//         const description = "Test Proposal (ETH)"
//         const amount = ethers.utils.parseEther("0.1")
//         const fundType = 1

//         await spendableVoting.connect(voter).depositFundsEth({ value: amount })
//         const contractBalance = await ethers.provider.getBalance(spendableVoting.address)
//         expect(contractBalance).to.be.equal(amount)

//         await expect(spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType))
//             .to.emit(spendableVoting, "NewProposal")
//             .withArgs(1, voter.address)
//     })

//     it("should end a proposal and transfer ETH", async function () {
//         const [_, voter, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter.address, 1000)
//         await erc20Token.connect(voter).approve(nft.address, 2000)
//         await nft.connect(voter).deposit(100, "week", true)

//         const description = "Test Proposal (ETH)"
//         const amount = ethers.utils.parseEther("0.1")
//         const fundType = 1
//         await spendableVoting.connect(voter).depositFundsEth({ value: amount })
//         await spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType)
//         await spendableVoting.connect(voter).voteProposal(1, 1) // Vote 'yes'

//         // // Send ETH to the contract
//         // await voter.sendTransaction({ to: spendableVoting.address, value: amount });

//         // Advance the time
//         await time.increase(time.duration.days(15))

//         // End the proposal
//         const tx = await spendableVoting.connect(voter).endProposalVote(1)
//         const receipt = await tx.wait()
//         const gasUsed = receipt.gasUsed
//         const gasPrice = tx.gasPrice
//         const gasCost = gasUsed.mul(gasPrice)

//         // Check if the payee has received the ETH
//         const payeeBalanceAfterProposal = await payee.getBalance()
//         expect(payeeBalanceAfterProposal).gt(ethers.utils.parseEther("10000"))
//     })

//     it("should end a review and transfer remaining ETH", async function () {
//         const [_, voter, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter.address, 1000)
//         await erc20Token.connect(voter).approve(nft.address, 2000)
//         await nft.connect(voter).deposit(100, "week", true)
//         const description = "Test Proposal (ETH)"
//         const amount = ethers.utils.parseEther("0.1")
//         const fundType = 2 // half_half
//         await spendableVoting.connect(voter).depositFundsEth({ value: amount })
//         await spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType)
//         await spendableVoting.connect(voter).voteProposal(1, 1) // Vote 'yes'

//         // Send ETH to the contract
//         // await voter.sendTransaction({ to: spendableVoting.address, value: amount });

//         // Advance the time
//         await time.increase(time.duration.days(15))

//         // End the proposal
//         await spendableVoting.connect(voter).endProposalVote(1)

//         //Create the review
//         await spendableVoting.connect(voter).createReview(1, "reviewing proposal")

//         // Vote on the review
//         await spendableVoting.connect(voter).voteReview(1, 0, 1) // Vote 'yes'

//         // Advance the time
//         await time.increase(time.duration.days(15))

//         // End the review
//         await spendableVoting.connect(voter).endReviewVote(1, 0)

//         // Check if the payee has received the remaining ETH
//         const payeeBalanceAfterReview = await payee.getBalance()
//         expect(payeeBalanceAfterReview).gt(ethers.utils.parseEther("10000"))
//     })
//     it("should not end a review when still open for vote", async function () {
//         const [_, voter, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter.address, 1000)
//         await erc20Token.connect(voter).approve(nft.address, 2000)
//         await nft.connect(voter).deposit(100, "week", true)
//         const description = "Test Proposal (ETH)"
//         const amount = ethers.utils.parseEther("0.1")
//         const fundType = 2 // half_half
//         await spendableVoting.connect(voter).depositFundsEth({ value: amount })
//         await spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType)
//         await spendableVoting.connect(voter).voteProposal(1, 1) // Vote 'yes'

//         // Send ETH to the contract
//         // await voter.sendTransaction({ to: spendableVoting.address, value: amount });

//         // Advance the time
//         await time.increase(time.duration.days(15))

//         // End the proposal
//         await spendableVoting.connect(voter).endProposalVote(1)

//         //Create the review
//         await spendableVoting.connect(voter).createReview(1, "reviewing proposal")

//         // Attempt to end the review before the voting period is over
//         await expect(spendableVoting.connect(voter).endReviewVote(1, 0)).to.be.revertedWith("REVIEW_OPEN_FOR_VOTE")
//     })

//     it("should not create a proposal with an invalid fund type", async function () {
//         const [_, voter, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter.address, 1000)
//         await erc20Token.connect(voter).approve(nft.address, 2000)
//         await nft.connect(voter).deposit(100, "week", true)
//         const description = "Invalid Fund Type Proposal"
//         const amount = ethers.utils.parseEther("0.1")
//         const invalidFundType = 99
//         await spendableVoting.depositFundsEth({ value: amount })
//         // Attempt to create a proposal with an invalid fund type
//         await expect(spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, invalidFundType)).to.be
//             .reverted
//     })

//     it("should reject a proposal when the majority of votes are 'no'", async function () {
//         const [_, voter1, voter2, voter3, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter1.address, 1000)
//         await erc20Token.connect(voter1).approve(nft.address, 2000)
//         await nft.connect(voter1).deposit(100, "week", true)

//         await erc20Token.mint(voter2.address, 1000)
//         await erc20Token.connect(voter2).approve(nft.address, 2000)
//         await nft.connect(voter2).deposit(100, "week", true)

//         await erc20Token.mint(voter3.address, 1000)
//         await erc20Token.connect(voter3).approve(nft.address, 2000)
//         await nft.connect(voter3).deposit(100, "week", true)

//         const description = "Test Proposal (ETH)"
//         const amount = ethers.utils.parseEther("0.1")
//         const fundType = 0
//         await spendableVoting.connect(voter1).depositFundsEth({ value: amount })
//         await spendableVoting.connect(voter1).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType)

//         // Voting
//         await spendableVoting.connect(voter1).voteProposal(1, 2) // Vote 'no'
//         await spendableVoting.connect(voter2).voteProposal(1, 2) // Vote 'no'
//         await spendableVoting.connect(voter3).voteProposal(1, 1) // Vote 'yes'

//         // Advance the time
//         await time.increase(time.duration.days(15))

//         // End the proposal
//         await spendableVoting.connect(voter1).endProposalVote(1)

//         // Check if the payee has not received the ETH
//         const payeeInitialBalance = ethers.utils.parseEther("10000")

//         expect(await payee.getBalance()).lte(payeeInitialBalance)
//     })

//     it("should not allow double voting", async function () {
//         const [_, voter, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter.address, 1000)
//         await erc20Token.connect(voter).approve(nft.address, 2000)
//         await nft.connect(voter).deposit(100, "week", true)

//         const description = "Test Proposal (ETH)"
//         const amount = ethers.utils.parseEther("0.1")
//         const fundType = 1
//         await spendableVoting.connect(voter).depositFundsEth({ value: amount })
//         await spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType)

//         // Vote 'yes'
//         await spendableVoting.connect(voter).voteProposal(1, 1)

//         // Attempt to vote again
//         await expect(spendableVoting.connect(voter).voteProposal(1, 1)).to.be.revertedWith("ALREADY_VOTED")
//     })

//     it("should not create a proposal without holding the NFT", async function () {
//         const [_, voter, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)
//         const nonHolder = await ethers.getSigner()

//         // Setup
//         const description = "Test Proposal (ETH)"
//         const amount = ethers.utils.parseEther("0.1")
//         const fundType = 1
//         await spendableVoting.connect(voter).depositFundsEth({ value: amount })

//         // Attempt to create a proposal without holding the NFT
//         await expect(
//             spendableVoting.connect(nonHolder).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType)
//         ).to.be.revertedWith("NOT_NFT_HOLDER")
//     })

//     it("should handle multiple proposals", async function () {
//         const [_, voter, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter.address, 1000)
//         await erc20Token.connect(voter).approve(nft.address, 2000)
//         await nft.connect(voter).deposit(100, "week", true)

//         const description1 = "Test Proposal 1 (ETH)"
//         const description2 = "Test Proposal 2 (ETH)"
//         const amount = ethers.utils.parseEther("0.1")
//         const fundType = 1
//         await spendableVoting.connect(voter).depositFundsEth({ value: amount })

//         // Create first proposal
//         await spendableVoting.connect(voter).createProposal(description1, payee.address, amount, constants.ZERO_ADDRESS, fundType)
//         const proposal1 = await spendableVoting.getProposal(1)
//         expect(proposal1.description).to.equal(description1)

//         // Create second proposal
//         await spendableVoting.connect(voter).createProposal(description2, payee.address, amount, constants.ZERO_ADDRESS, fundType)
//         const proposal2 = await spendableVoting.getProposal(2)
//         expect(proposal2.description).to.equal(description2)
//     })

//     it("should not allow double voting", async function () {
//         const [_, voter, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter.address, 1000)
//         await erc20Token.connect(voter).approve(nft.address, 2000)
//         await nft.connect(voter).deposit(100, "week", true)

//         const description = "Test Proposal (ETH)"
//         const amount = ethers.utils.parseEther("0.1")
//         const fundType = 1
//         await spendableVoting.connect(voter).depositFundsEth({ value: amount })
//         await spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType)

//         // Vote 'yes'
//         await spendableVoting.connect(voter).voteProposal(1, 1)

//         // Attempt to vote again
//         await expect(spendableVoting.connect(voter).voteProposal(1, 1)).to.be.revertedWith("ALREADY_VOTED")
//     })

//     it("should not create a proposal with zero amount", async function () {
//         const [_, voter, payee] = await ethers.getSigners()
//         const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter.address, 1000)
//         await erc20Token.connect(voter).approve(nft.address, 2000)
//         await nft.connect(voter).deposit(100, "week", true)

//         const description = "Zero Amount Proposal"
//         const zeroAmount = ethers.utils.parseEther("0")
//         const fundType = 1

//         // Attempt to create a proposal with zero amount
//         await expect(spendableVoting.connect(voter).createProposal(description, payee.address, zeroAmount, constants.ZERO_ADDRESS, fundType)).to.be
//             .reverted
//     })

//     it("should not vote on a non-existent proposal", async function () {
//         const { voter, payee, erc20Token, nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS)

//         // Setup
//         await erc20Token.mint(voter.address, 1000)
//         await erc20Token.connect(voter).approve(nft.address, 2000)
//         await nft.connect(voter).deposit(100, "week", true)

//         // Attempt to vote on a non-existent proposal
//         await expect(spendableVoting.connect(voter).voteProposal(1, 0)).to.be.reverted
//     })
// })
