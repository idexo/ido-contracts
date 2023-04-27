const Voting = artifacts.require("contracts/voting/SpendableVotingByStakeNFTHolder.sol")
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

  const NFT = await ethers.getContractFactory("StakePoolFlexLock");
  const nft = await NFT.deploy("NFT", "NFT", "", 100, erc20Token.address, erc20Token.address);
  const stakeTypes = await nft.addStakeTypes(["day", "week"], [1, 7])

  // If no payment token address is provided, use the ERC20 token address
  if (!paymentTokenAddress) {
    paymentTokenAddress = erc20Token.address;
  }  

  // Deploy the SpendableVotingByStakeNFTHolder contract
  const SpendableVotingByStakeNFTHolder = await ethers.getContractFactory("SpendableVotingByStakeNFTHolder");
  const spendableVoting = await SpendableVotingByStakeNFTHolder.deploy(14, 14, [nft.address]);

  return { owner, voter, payee, erc20Token, nft, spendableVoting };
}

describe("SpendableVotingByStakeNFTHolder", function () {
  it("should create a proposal", async function () {
    const { voter, payee, erc20Token, nft, spendableVoting } = await deployContracts();

    // Setup (e.g., mint NFT for voter, approve ERC20 tokens to the contract)
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)
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

    
    // Setup (e.g., mint NFT for voter, approve ERC20 tokens to the contract)
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)
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
    // Setup (e.g., mint NFT for voter, approve ERC20 tokens to the contract)
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)
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
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)
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

describe("SpendableVotingByStakeNFTHolder (ETH)", function () {
  // ...
  it("should create a proposal with Ethereum as payment token", async function () {

    const [_, voter, payee] = await ethers.getSigners();
    const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 1000)
    await nft.connect(voter).deposit(100, "week", true)

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
    const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)

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
    const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)
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
    const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)
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
    const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)
    const description = "Invalid Fund Type Proposal";
    const amount = ethers.utils.parseEther("0.1");
    const invalidFundType = 99;
    await spendableVoting.depositFundsEth({ value: amount })
    // Attempt to create a proposal with an invalid fund type
    await expect(spendableVoting.connect(voter).createProposal(description, payee.address, amount, constants.ZERO_ADDRESS, invalidFundType)).to.be.reverted;
  });

  it("should reject a proposal when the majority of votes are 'no'", async function () {
  const [_, voter1, voter2, voter3, payee] = await ethers.getSigners();
  const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

  // Setup
  await erc20Token.mint(voter1.address, 1000)
  await erc20Token.connect(voter1).approve(nft.address, 2000)
  await nft.connect(voter1).deposit(100, "week", true)

  await erc20Token.mint(voter2.address, 1000)
  await erc20Token.connect(voter2).approve(nft.address, 2000)
  await nft.connect(voter2).deposit(100, "week", true)

  await erc20Token.mint(voter3.address, 1000)
  await erc20Token.connect(voter3).approve(nft.address, 2000)
  await nft.connect(voter3).deposit(100, "week", true)

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
    const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)

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
    const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);
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
    const { nft, erc20Token ,spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)

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
    const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)

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
    const { nft, erc20Token, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)

    const description = "Zero Amount Proposal";
    const zeroAmount = ethers.utils.parseEther("0");
    const fundType = 1;

    // Attempt to create a proposal with zero amount
    await expect(spendableVoting.connect(voter).createProposal(description, payee.address, zeroAmount, constants.ZERO_ADDRESS, fundType)).to.be.reverted;
  });

  it("should not vote on a non-existent proposal", async function () {
    const { voter, payee, erc20Token, nft, spendableVoting } = await deployContracts(constants.ZERO_ADDRESS);

    // Setup
    await erc20Token.mint(voter.address, 1000)
    await erc20Token.connect(voter).approve(nft.address, 2000)
    await nft.connect(voter).deposit(100, "week", true)

    // Attempt to vote on a non-existent proposal
    await expect(spendableVoting.connect(voter).voteProposal(1, 0)).to.be.reverted;
  });

  

  

  

 
});



