const Voting = artifacts.require("contracts/voting/SpendableVotingByNFTHolder.sol")
const StakePool = artifacts.require("StakePool")
const ERC20 = artifacts.require("ERC20Mock")
const { ethers } = require("hardhat");

const { Contract } = require("@ethersproject/contracts")
const { expect } = require("chai")
const { duration } = require("./helpers/time")
const { BN, constants, expectEvent, expectRevert, time } = require("@openzeppelin/test-helpers")
const { toWei } = require("web3-utils")
// const time = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")

async function deployContracts(paymentTokenAddress = undefined) {
  const [owner, voter, payee] = await ethers.getSigners();
  console.log()

  // Deploy the necessary token contracts
  const ERC20Token = await ethers.getContractFactory("ERC20Mock");
  const erc20Token = await ERC20Token.deploy("ERC20 Token", "TKN");

  const NFT = await ethers.getContractFactory("StandardCappedNFTCollection");
  const nft = await NFT.deploy("NFT", "NFT", "", 100);

  // If no payment token address is provided, use the ERC20 token address
  if (!paymentTokenAddress) {
    paymentTokenAddress = erc20Token.address;
  }  

  // Deploy the SpendableVotingByNFTHolder contract
  const SpendableVotingByNFTHolder = await ethers.getContractFactory("SpendableVotingByNFTHolder");
  const spendableVoting = await SpendableVotingByNFTHolder.deploy(14, 14, [nft.address]);

  return { owner, voter, payee, erc20Token, nft, spendableVoting };
}

describe("SpendableVotingByNFTHolder", function () {
  it("should create a proposal", async function () {
    const { voter, payee, erc20Token, nft, spendableVoting } = await deployContracts();

    // Setup (e.g., mint NFT for voter, approve ERC20 tokens to the contract)
    await nft.mintNFT(voter.address, "someurl.html");
    await erc20Token.mint(spendableVoting.address, 1000);

    const description = "Test Proposal";
    const amount = 100;
    const fundType = 1;

    await expect(spendableVoting.connect(voter).createProposal(description, payee.address, amount, erc20Token.address, fundType))
      .to.emit(spendableVoting, "NewProposal")
      .withArgs(1, voter.address);
  });

  it("should not create a proposal without NFT holder", async function () {
    const { owner, payee, erc20Token, nft, spendableVoting } = await deployContracts();

    const description = "Test Proposal";
    const amount = 100;
    const fundType = 1;

    await expectRevert(
      spendableVoting.connect(owner).createProposal(description, payee.address, amount, erc20Token.address, fundType),
      "NOT_NFT_HOLDER"
    );
  });

  it("should vote on a proposal", async function () {
    const { voter, payee, erc20Token, nft, spendableVoting } = await deployContracts();

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    await erc20Token.mint(spendableVoting.address, 1000);
    const description = "Test Proposal";
    const amount = 100;
    const fundType = 1;
    await spendableVoting.connect(voter).createProposal(description, payee.address, amount, erc20Token.address, fundType);

    // Vote
    await spendableVoting.connect(voter).voteProposal(1, 1)
    // await expect() _votedProp[proposalId_][msg.sender] = true;
  });

  it("should end a proposal and transfer funds", async function () {
    const { voter, payee, erc20Token, nft, spendableVoting } = await deployContracts();

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    await erc20Token.mint(spendableVoting.address, 1000);
    const description = "Test Proposal";
    const amount = 100;
    const fundType = 1;
    await spendableVoting.connect(voter).createProposal(description, payee.address, amount, erc20Token.address, fundType);
    await spendableVoting.connect(voter).voteProposal(1, 1); // Vote 'yes'

    console.log(spendableVoting.proposalIds())

    // Advance the time
    await time.increase(time.duration.days(15));

    // End the proposal
    await spendableVoting.connect(voter).endProposalVote(1)

    // Check if the payee has received the funds
    expect(await erc20Token.balanceOf(payee.address)).to.equal(amount);
  });

  it("should end a review and transfer remaining funds", async function () {
    const { voter, payee, erc20Token, nft, spendableVoting } = await deployContracts();

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    await erc20Token.mint(spendableVoting.address, 1000);
    const description = "Test Proposal";
    const amount = 100;
    const fundType = 2; // half_half
    await spendableVoting.connect(voter).createProposal(description, payee.address, amount, erc20Token.address, fundType);
    await spendableVoting.connect(voter).voteProposal(1, 1); // Vote 'yes'
    console.log(spendableVoting.proposalIds())

    // Advance the time
    await time.increase(time.duration.days(15));

    // End the proposal
    await spendableVoting.connect(voter).endProposalVote(1);

    //Create the review
    await spendableVoting.connect(voter).createReview(1, "reviewing proposal");

    // Vote on the review
    await spendableVoting.connect(voter).voteReview(1, 0, 1); // Vote 'yes'


    // Advance the time
    await time.increase(time.duration.days(15));

    // End the review
    await spendableVoting.connect(voter).endReviewVote(1, 0)

    // Check if the payee has received the remaining funds
    expect(await erc20Token.balanceOf(payee.address)).to.equal(amount);
  });

  // Add more tests...
});

describe("SpendableVotingByNFTHolder (ETH)", function () {
  // ...
  it("should create a proposal with Ethereum as payment token", async function () {

    const [_, voter, payee] = await ethers.getSigners();
    const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");

    const description = "Test Proposal (ETH)";
    const amount = ethers.utils.parseEther("0.1");
    const fundType = 1;

    await spendableVoting.connect(voter).depositFundsEth({ value: amount })
    const contractBalance = await ethers.provider.getBalance(spendableVoting.address);
    expect(contractBalance).to.be.equal(amount);

    await expect(spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType))
      .to.emit(spendableVoting, "NewProposal")
      .withArgs(1, voter.address);
  });

  it("should end a proposal and transfer ETH", async function () {
    const [_, voter, payee] = await ethers.getSigners();
    const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    const description = "Test Proposal (ETH)";
    const amount = ethers.utils.parseEther("0.1");
    const fundType = 1;
    await spendableVoting.connect(voter).depositFundsEth({ value: amount })
    await spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType);
    await spendableVoting.connect(voter).voteProposal(1, 1); // Vote 'yes'

    // // Send ETH to the contract
    // await voter.sendTransaction({ to: spendableVoting.address, value: amount });

    // Advance the time
    await time.increase(time.duration.days(15));

    // End the proposal
    const tx = await spendableVoting.connect(voter).endProposalVote(1);
    const receipt = await tx.wait();
    const gasUsed = receipt.gasUsed;
    const gasPrice = tx.gasPrice;
    const gasCost = gasUsed.mul(gasPrice);

    // Check if the payee has received the ETH
    const payeeBalanceAfterProposal = await payee.getBalance();
    expect(payeeBalanceAfterProposal).gt(ethers.utils.parseEther("10000"));
  })

  it("should end a review and transfer remaining ETH", async function () {
    const [_, voter, payee] = await ethers.getSigners();
    const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    const description = "Test Proposal (ETH)";
    const amount = ethers.utils.parseEther("0.1");
    const fundType = 2; // half_half
    await spendableVoting.connect(voter).depositFundsEth({ value: amount })
    await spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType);
    await spendableVoting.connect(voter).voteProposal(1, 1); // Vote 'yes'

    // Send ETH to the contract
    // await voter.sendTransaction({ to: spendableVoting.address, value: amount });

    // Advance the time
    await time.increase(time.duration.days(15));

    // End the proposal
    await spendableVoting.connect(voter).endProposalVote(1);

    //Create the review
    await spendableVoting.connect(voter).createReview(1, "reviewing proposal");

    // Vote on the review
    await spendableVoting.connect(voter).voteReview(1, 0, 1); // Vote 'yes'

    // Advance the time
    await time.increase(time.duration.days(15));

    // End the review
    await spendableVoting.connect(voter).endReviewVote(1, 0)

    // Check if the payee has received the remaining ETH
    const payeeBalanceAfterReview = await payee.getBalance();
    expect(payeeBalanceAfterReview).gt(ethers.utils.parseEther("10000"));
  });
  it("should not end a review when still open for vote", async function () {
    const [_, voter, payee] = await ethers.getSigners();
    const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    const description = "Test Proposal (ETH)";
    const amount = ethers.utils.parseEther("0.1");
    const fundType = 2; // half_half
    await spendableVoting.connect(voter).depositFundsEth({ value: amount })
    await spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType);
    await spendableVoting.connect(voter).voteProposal(1, 1); // Vote 'yes'

    // Send ETH to the contract
    // await voter.sendTransaction({ to: spendableVoting.address, value: amount });

    // Advance the time
    await time.increase(time.duration.days(15));

    // End the proposal
    await spendableVoting.connect(voter).endProposalVote(1);

    //Create the review
    await spendableVoting.connect(voter).createReview(1, "reviewing proposal");

    // Attempt to end the review before the voting period is over
    await expect(spendableVoting.connect(voter).endReviewVote(1, 0)).to.be.revertedWith("REVIEW_OPEN_FOR_VOTE");
  });

  it("should not create a proposal with an invalid fund type", async function () {
    const [_, voter, payee] = await ethers.getSigners();
    const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    const description = "Invalid Fund Type Proposal";
    const amount = ethers.utils.parseEther("0.1");
    const invalidFundType = 99;
    await spendableVoting.depositFundsEth({ value: amount })
    // Attempt to create a proposal with an invalid fund type
    await expect(spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, invalidFundType)).to.be.reverted;
  });

  it("should reject a proposal when the majority of votes are 'no'", async function () {
  const [_, voter1, voter2, voter3, payee] = await ethers.getSigners();
  const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

  // Setup
  await nft.mintNFT(voter1.address, "someurl.html");
  await nft.mintNFT(voter2.address, "someurl.html");
  await nft.mintNFT(voter3.address, "someurl.html");
  const description = "Test Proposal (ETH)";
  const amount = ethers.utils.parseEther("0.1");
  const fundType = 0;
  await spendableVoting.connect(voter1).depositFundsEth({ value: amount })
  await spendableVoting.connect(voter1).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType);

  // Voting
  await spendableVoting.connect(voter1).voteProposal(1, 2); // Vote 'no'
  await spendableVoting.connect(voter2).voteProposal(1, 2); // Vote 'no'
  await spendableVoting.connect(voter3).voteProposal(1, 1); // Vote 'yes'

  // Advance the time
  await time.increase(time.duration.days(15));

  // End the proposal
  await spendableVoting.connect(voter1).endProposalVote(1);

  // Check if the payee has not received the ETH
  const payeeInitialBalance = ethers.utils.parseEther("10000");
  expect(await payee.getBalance()).lt(payeeInitialBalance);
});


  it("should not allow double voting", async function () {
    const [_, voter, payee] = await ethers.getSigners();
    const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    const description = "Test Proposal (ETH)";
    const amount = ethers.utils.parseEther("0.1");
    const fundType = 1;
    await spendableVoting.connect(voter).depositFundsEth({ value: amount })
    await spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType);

    // Vote 'yes'
    await spendableVoting.connect(voter).voteProposal(1, 1);

    // Attempt to vote again
    await expect(spendableVoting.connect(voter).voteProposal(1, 1)).to.be.revertedWith("ALREADY_VOTED");
  });

 
  it("should not create a proposal without holding the NFT", async function () {
    const [_, voter, payee] = await ethers.getSigners();
    const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);
    const nonHolder = await ethers.getSigner();

    // Setup
    const description = "Test Proposal (ETH)";
    const amount = ethers.utils.parseEther("0.1");
    const fundType = 1;
    await spendableVoting.connect(voter).depositFundsEth({ value: amount })

    // Attempt to create a proposal without holding the NFT
    await expect(spendableVoting.connect(nonHolder).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType)).to.be.revertedWith("NOT_NFT_HOLDER");
  });

  it("should handle multiple proposals", async function () {
    const [_, voter, payee] = await ethers.getSigners();
    const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    const description1 = "Test Proposal 1 (ETH)";
    const description2 = "Test Proposal 2 (ETH)";
    const amount = ethers.utils.parseEther("0.1");
    const fundType = 1;
    await spendableVoting.connect(voter).depositFundsEth({ value: amount })

    // Create first proposal
    await spendableVoting.connect(voter).createProposal(description1, payee.address, amount, constants.ZERO_ADDRESS, fundType);
    const proposal1 = await spendableVoting.getProposal(1);
    expect(proposal1.description).to.equal(description1);

    // Create second proposal
    await spendableVoting.connect(voter).createProposal(description2, payee.address, amount, constants.ZERO_ADDRESS, fundType);
    const proposal2 = await spendableVoting.getProposal(2);
    expect(proposal2.description).to.equal(description2);
  });

  

  it("should not allow double voting", async function () {
    const [_, voter, payee] = await ethers.getSigners();
    const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    const description = "Test Proposal (ETH)";
    const amount = ethers.utils.parseEther("0.1");
    const fundType = 1;
    await spendableVoting.connect(voter).depositFundsEth({ value: amount })
    await spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, fundType);

    // Vote 'yes'
    await spendableVoting.connect(voter).voteProposal(1, 1);

    // Attempt to vote again
    await expect(spendableVoting.connect(voter).voteProposal(1, 1)).to.be.revertedWith("ALREADY_VOTED");
  });

 


  it("should not create a proposal with zero amount", async function () {
    const [_, voter, payee] = await ethers.getSigners();
    const { nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");
    const description = "Zero Amount Proposal";
    const zeroAmount = ethers.utils.parseEther("0");
    const fundType = 1;

    // Attempt to create a proposal with zero amount
    await expect(spendableVoting.connect(voter).createProposal(description, payee.address, zeroAmount, constants.ZERO_ADDRESS, fundType)).to.be.reverted;
  });

  it("should not vote on a non-existent proposal", async function () {
    const { voter, payee, nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await nft.mintNFT(voter.address, "someurl.html");

    // Attempt to vote on a non-existent proposal
    await expect(spendableVoting.connect(voter).voteProposal(1, 0)).to.be.reverted;
  });

  

  

  

 
});



contract("Voting", async (accounts) => {
    let ido, usdt
    let voting, sPool1, sPool2, sPool3, sPool4
    const [alice, bob, carol, darren, payeeWallet] = accounts

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
            await usdt.mint(carol, web3.utils.toWei(new BN(5000)))
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
                    await sPool1.deposit(web3.utils.toWei(new BN(5200)), { from: carol })
                    await sPool1.getStakeInfo(2).then((res) => {
                        expect(res[0].toString()).to.eq("5200000000000000000000")
                    })
                    const aliceIDOBalance = await ido.balanceOf(alice)
                    expect(aliceIDOBalance.toString()).to.eq("194800000000000000000000")
                })
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
                    voting.createProposal("Test Proposal 1", payeeWallet, web3.utils.toWei(new BN(1)), usdt.address, 1, { from: alice }),
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
            it("create new proposal #1", async () => {
                voting.createProposal("Test Proposal 1", payeeWallet, web3.utils.toWei(new BN(1000)), usdt.address, 1, { from: alice })
            })
            it("create new proposal #2", async () => {
                voting.createProposal("Test Proposal 2", payeeWallet, web3.utils.toWei(new BN(3000)), usdt.address, 2, { from: alice })
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
                await voting.voteProposal(1, 2, { from: alice })
                const proposal = await voting.getProposal(1)
                await voting.getProposal(1).then((proposal) => {
                    expect(proposal.options[1]["votes"]).to.eq("1")
                })
            })

            it("should vote proposal #2", async () => {
                await voting.voteProposal(2, 1, { from: alice })
                await voting.voteProposal(2, 1, { from: bob })
                await voting.voteProposal(2, 1, { from: carol })
                const proposal = await voting.getProposal(1)
                await voting.getProposal(2).then((proposal) => {
                    expect(proposal.options[0]["votes"]).to.eq("3")
                })
            })

            describe("reverts if", async () => {
                it("VOTE_ENDED", async () => {
                    let snapShot = await timeTraveler.takeSnapshot()
                    await timeTraveler.advanceTime(duration.days(20))
                    await expectRevert(voting.voteProposal(1, 1, { from: alice }), "VOTE_ENDED")
                    await timeTraveler.revertToSnapshot(snapShot["result"])
                })
                it("ALREADY_VOTED", async () => {
                    await expectRevert(voting.voteProposal(1, 1, { from: alice }), "ALREADY_VOTED")
                })
                it("NOT_NFT_HOLDER", async () => {
                    await expectRevert(voting.voteProposal(1, 1, { from: darren }), "NOT_NFT_HOLDER")
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

        describe("#Review reverts", async () => {
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
                it("REJECTED_PROPOSAL", async () => {
                    let snapShot = await timeTraveler.takeSnapshot()
                    await timeTraveler.advanceTime(duration.days(20))
                    await voting.endProposalVote(1, { from: alice })
                    await expectRevert(voting.createReview(1, "First proposal id #1 review", { from: alice }), "REJECTED_PROPOSAL")
                    await timeTraveler.revertToSnapshot(snapShot["result"])
                })
            })
        })

        describe("#End Proposal", async () => {
            describe("reverts if", async () => {
                it("OPEN_FOR_VOTE", async () => {
                    await expectRevert(voting.endProposalVote(1, { from: alice }), "OPEN_FOR_VOTE")
                })
                it("ALREADY_ENDED", async () => {
                    let snapShot = await timeTraveler.takeSnapshot()
                    await timeTraveler.advanceTime(duration.days(20))
                    await voting.endProposalVote(1, { from: alice })
                    await expectRevert(voting.endProposalVote(1, { from: alice }), "ALREADY_ENDED")
                    await timeTraveler.revertToSnapshot(snapShot["result"])
                })
                it("INSUFFICIENT_FUNDS_CALL_ADMIN", async () => {
                    let snapShot = await timeTraveler.takeSnapshot()
                    await voting.voteProposal(1, 1, { from: bob })
                    await voting.voteProposal(1, 1, { from: carol })
                    await timeTraveler.advanceTime(duration.days(20))
                    voting.sweep(usdt.address, carol, web3.utils.toWei(new BN(5000)))
                    await expectRevert(voting.endProposalVote(1, { from: alice }), "INSUFFICIENT_FUNDS_CALL_ADMIN")
                    await timeTraveler.revertToSnapshot(snapShot["result"])
                })
            })
        })

        describe("#Review", async () => {
            it("should create review", async () => {
                await voting.voteProposal(1, 1, { from: bob })
                await voting.voteProposal(1, 1, { from: carol })
                await timeTraveler.advanceTime(duration.days(20))
                await voting.endProposalVote(1, { from: alice })
                await voting.createReview(1, "First proposal id #1 review", { from: alice })
            })

            it("should vote review", async () => {
                let review = await voting.getReview(1, 0) // review id 0????
                // console.log(review)
                await voting.voteReview(1, 0, 1, { from: alice })
                await voting.voteReview(1, 0, 1, { from: bob })
                await voting.voteReview(1, 0, 2, { from: carol })
                review = await voting.getReview(1, 0)
                // console.log(review)
            })

            describe("reverts if", async () => {
                it("VOTE_ENDED", async () => {
                    await expectRevert(voting.voteReview(1, 0, 1, { from: alice }), "VOTE_ENDED")
                })
            })

            it("should end review", async () => {
                await timeTraveler.advanceTime(duration.days(20))
                await voting.endReviewVote(1, 0, { from: alice })
            })

            describe("handle Proposal #2", async () => {
                it("should end proposal #2", async () => {
                    const proposal = await voting.getProposal(2)
                    // console.log(proposal)
                    await voting.endProposalVote(2, { from: alice })
                    const payeeBalance = await usdt.balanceOf(payeeWallet)
                    // console.log("PAYEE BALANCE::", payeeBalance.toString())
                })

                it("should create and reject review for proposal #2", async () => {
                    let snapShot = await timeTraveler.takeSnapshot()
                    await voting.createReview(2, "Second proposal id #2 review", { from: alice })
                    await voting.voteReview(2, 0, 2, { from: alice })
                    await voting.voteReview(2, 0, 2, { from: bob })
                    await voting.voteReview(2, 0, 1, { from: carol })
                    await timeTraveler.advanceTime(duration.days(20))
                    await voting.endReviewVote(2, 0, { from: alice })
                    const payeeBalance = await usdt.balanceOf(payeeWallet)
                    // console.log("PAYEE BALANCE::", payeeBalance.toString())
                    await timeTraveler.revertToSnapshot(snapShot["result"])
                })

                it("should create and approve review for proposal #2", async () => {
                    await voting.createReview(2, "Second proposal id #2 review", { from: alice })
                    await voting.voteReview(2, 0, 1, { from: alice })
                    await voting.voteReview(2, 0, 1, { from: bob })
                    await voting.voteReview(2, 0, 2, { from: carol })
                    await timeTraveler.advanceTime(duration.days(20))
                    await voting.endReviewVote(2, 0, { from: alice })
                    const payeeBalance = await usdt.balanceOf(payeeWallet)
                    // console.log("PAYEE BALANCE::", payeeBalance.toString())
                })
            })
        })
    })

    describe("#Sweep", async () => {
        it("should sweep funds from contract", async () => {
            const contractBalance = await usdt.balanceOf(voting.address)
            // console.log("CONTRACT BALANCE::", contractBalance.toString())

            voting.sweep(usdt.address, carol, web3.utils.toWei(new BN(1000)))
        })
    })
})
