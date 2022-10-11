const { expect } = require("chai");
const { ethers } = require("hardhat");
const { duration, increase } = require("./helpers/time");
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

const contractName = "SpendableVotingByNFTHolder";
const nftContractName = "ERC721Mock";
const rewardContractName = "ERC20Mock";

describe(`::Contract -> ${contractName}`, () => {
  const DOMAIN = "https://idexo.com/";
  const minPoolStakeAmount = 100;

  const name = "My Mock Token";
  const symbol = "MMT";
  const decimals = 18;

  let contract, stakePool1, stakePool2, reward;
  let deployer, alice, bob, carol, darren;
  before(async () => {
    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    const Staking = await ethers.getContractFactory("StakePoolFlexLock");
    const Voting = await ethers.getContractFactory(contractName);
    const signers = await ethers.getSigners();

    token = await ERC20.deploy(name, symbol, decimals);
    ido = await ERC20.deploy("Idexo Community Token", "IDO", 18);
    reward = await ERC20.deploy("Reward Coin", "RWD", 6);

    stakePool1 = await Staking.deploy(
      "Idexo Stake Token 1",
      "IDS1",
      DOMAIN,
      minPoolStakeAmount,
      ido.address,
      reward.address
    );

    stakePool2 = await Staking.deploy(
      "Idexo Stake Token 2",
      "IDS2",
      DOMAIN,
      minPoolStakeAmount,
      ido.address,
      reward.address
    );

    contract = await Voting.deploy(14, 7, [
      stakePool1.address,
      stakePool2.address,
    ]);

    [deployer, alice, bob, carol, darren] = signers;
  });

  describe("# StakeToken Preparing", async () => {
    it("should add stakeType", async () => {
      await stakePool1.addStakeType("DAY", 1);
      await stakePool2.addStakeType("DAY", 1);
    });

    it("should get added stakeTypes", async () => {
      const stakeTypes = await stakePool1.getStakeTypes();
      // console.log(stakeTypes)
    });

    describe("preparing stakes tokens", async () => {
      it("Should mint to alice", async () => {
        let decimals = await ido.decimals();
        // console.log("Token decimals:", decimals);

        await ido.mint(alice.address, (500 * 10 ** decimals).toString());
        let balance = await ido.balanceOf(alice.address);

        expect(balance / 10 ** decimals).to.equal(500);

        await ido.connect(alice).approve(stakePool1.address, 500);

        await ido.mint(bob.address, (500 * 10 ** decimals).toString());
        let balance2 = await ido.balanceOf(bob.address);

        // console.log(balance);
        expect(balance2 / 10 ** decimals).to.equal(500);

        await ido.connect(bob).approve(stakePool1.address, 5000);
      });
      it("should stake 1", async () => {
        await stakePool1
          .connect(alice)
          .getEligibleStakeAmount(0)
          .then((res) => {
            expect(res.toString()).to.eq("0");
          });
        await stakePool1.isHolder(alice.address).then((res) => {
          expect(res.toString()).to.eq("false");
        });

        await expect(
          stakePool1.connect(alice).deposit(500, "DAY", false)
        ).to.emit(stakePool1, "Deposited");
        await ido.balanceOf(stakePool1.address).then((res) => {
          expect(res.toString()).to.eq("500");
        });
      });

      it("stake info 1", async () => {
        await stakePool1.getStakeInfo(1).then((res) => {
          expect(res[0].toString()).to.eq("500");
        });

        await stakePool1.getStakeType(1).then((res) => {
          expect(res).to.eq("DAY");
        });

        await stakePool1.currentSupply().then((res) => {
          expect(res.toString()).to.eq("1");
        });

        await stakePool1.connect(alice).setCompounding(1, true);

        await stakePool1.isCompounding(1).then((res) => {
          expect(res).to.eq(true);
        });

        await stakePool1.getStakeTokenIds(alice.address).then((res) => {
          expect(res[0].toString()).to.eq("1");
        });
      });
      it("should stake 2", async () => {
        let number = await ethers.provider.getBlockNumber();
        let block = await ethers.provider.getBlock(number);
        await expect(
          stakePool1.connect(bob).deposit(5000, "DAY", false)
        ).to.emit(stakePool1, "Deposited");
        await stakePool1.getStakeInfo(2).then((res) => {
          expect(res[0].toString()).to.eq("5000");
        });
        await stakePool1.isHolder(bob.address).then((res) => {
          expect(res.toString()).to.eq("true");
        });
      });

      it("should stake in pool2", async () => {
        let decimals = await ido.decimals();
        await ido.mint(alice.address, (500 * 10 ** decimals).toString());
        let balance2 = await ido.balanceOf(alice.address);

        expect(balance2 / 10 ** decimals).to.equal(1000);

        await ido.connect(alice).approve(stakePool2.address, 5000);

        await expect(
          stakePool2.connect(alice).deposit(5000, "DAY", false)
        ).to.emit(stakePool2, "Deposited");
        await stakePool2.getStakeInfo(1).then((res) => {
          expect(res[0].toString()).to.eq("5000");
        });
        await stakePool2.isHolder(alice.address).then((res) => {
          expect(res.toString()).to.eq("true");
        });
      });
    });
  });
  describe("SpendableVoting", () => {
    it("Should mint to alice", async () => {
      let decimals = await token.decimals();
      // console.log("Token decimals:", decimals);

      await token.mint(alice.address, (10 * 10 ** decimals).toString());
      let balance = await token.balanceOf(alice.address);

      // console.log(balance);
      expect(balance / 10 ** decimals).to.equal(10);
    });

    it("Should verify state", async () => {
      let decimals = await token.decimals();
      let balance = await token.balanceOf(alice.address);

      // console.log(balance);
      expect(balance / 10 ** decimals).to.equal(10);

      let votingBalance = await token.balanceOf(contract.address);
      // console.log(votingBalance);

      await token.connect(alice).transfer(contract.address, 9);

      votingBalance = await token.balanceOf(contract.address);
      // console.log("Balance after transfer: ", votingBalance);

      await contract.connect(deployer).sweep(token.address, bob.address, 9);

      let bobBalance = await token.balanceOf(bob.address);
      // console.log("Bob balance:", bobBalance);

      votingBalance = await token.balanceOf(contract.address);
      // console.log("Balance after transfer: ", votingBalance);
    });

    describe("Should create and get a Proposal", () => {
      it("Should create a New Proposal", async () => {
        // add funds to this contract
        await ido.mint(contract.address, 5000);

        const tx = await contract
          .connect(alice)
          .createProposal(
            "My first proposal",
            carol.address,
            5000,
            ido.address,
            2
          );
        const receipt = await ethers.provider.getTransactionReceipt(tx.hash);
        const interface = new ethers.utils.Interface([
          "event NewProposal(uint8 proposalId, address indexed proposer)",
        ]);
        const data = receipt.logs[0].data;
        const topics = receipt.logs[0].topics;
        const event = interface.decodeEventLog("NewProposal", data, topics);
        expect(event.proposalId).to.equal(1);
        expect(event.proposer).to.equal(alice.address);

        await expect(
          contract
            .connect(alice)
            .createProposal(
              "My second proposal",
              carol.address,
              5000,
              ido.address,
              2
            )
        )
          .to.emit(contract, "NewProposal")
          .withArgs(2, alice.address);
      });

      it("Should get a Proposal", async () => {
        const totalProposals = await contract.proposalIds();

        if (totalProposals > 1) {
          for (let p = 1; p <= totalProposals; p++) {
            const proposal = await contract.connect(alice).getProposal(p);

            // console.log(proposal);
          }
        }
      });

      it("Should deposit funds", async () => {
        await token.mint(bob.address, 1000);
        await token.mint(deployer.address, 5000);

        await token.connect(deployer).approve(contract.address, 5000);

        await contract.depositFunds(token.address, 5000);

        votingBalance = await token.balanceOf(contract.address);
        // console.log("Balance after transfer: ", votingBalance);
      });

      it("Should vote a proposal", async () => {
        await contract.connect(bob).voteProposal(1, 1);
        await contract.connect(alice).voteProposal(1, 1);
        await contract.connect(alice).voteProposal(2, 2);
      });

      it("Should add comment about proposal", async () => {
        await contract
          .connect(bob)
          .createComment(1, "I think that this proposal should not pass.");

        await contract
          .connect(alice)
          .createComment(2, "I'm not sure about it.");

        let comments1 = await contract.getComments(1);

        // console.log(comments1)

        let comments2 = await contract.getComments(2);

        // console.log(comments2)
      });

      it("Should get weight", async () => {
        let balanceOfStakeContract = await ido.balanceOf(stakePool1.address);
        // console.log("Balance of staking contract", balanceOfStakeContract);
        let stakeBalance = await stakePool1.isHolder(alice.address);
        // console.log(stakeBalance);

        const proposal = await contract.connect(alice).getProposal(1);
        const proposal2 = await contract.connect(alice).getProposal(2);

        await stakePool1.getStakeInfo(1).then((res) => {
          // console.log("Staked: ", res.toString());
        });
        await stakePool1.getStakeInfo(2).then((res) => {
          // console.log("Staked: ", res.toString());
        });
        // console.log(proposal);
        // console.log(proposal2);
      });

      it("Should end Proposal", async () => {
        let votingIdoBal = await ido.balanceOf(contract.address);
        // console.log(votingIdoBal.toString());
        await increase(duration.days(20));

        await contract.connect(alice).endProposalVote(1);
        const proposal = await contract.connect(alice).getProposal(1);

        let carolBalance = await ido.balanceOf(carol.address);
        // console.log(carolBalance.toString());
        votingIdoBal = await ido.balanceOf(contract.address);
        // console.log(votingIdoBal.toString());

        // await timeTraveler.revertToSnapshot(snapShot["result"]);
      });

      it("Should create and get review of a Proposal", async () => {
        await contract.connect(alice).createReview(1, "My first review");
        await contract.connect(alice).createReview(1, "My second review");
        await contract
          .connect(alice)
          .createReview(2, "My first review on another");

        let reviewByProposal = await contract.connect(alice).getReviewIds(1);
        // console.log("Total of reviews for this proposalId", reviewByProposal);

        for (let index = 0; index < reviewByProposal.toString(); index++) {
          const review = await contract.connect(alice).getReview(1, index);

          // console.log(review);
        }
      });

      it("Should vote in a review of a Proposal", async () => {
        await contract.connect(alice).voteReview(1, 0, 1);
        await contract.connect(bob).voteReview(1, 0, 1);

        let reviewByProposal = await contract.connect(alice).getReviewIds(1);
        // console.log("Total of reviews for this proposalId", reviewByProposal);

        for (let index = 0; index < reviewByProposal.toString(); index++) {
          const review = await contract.connect(alice).getReview(1, index);

          // console.log(review);
        }
      });
      it("Should end a Review", async () => {
        let votingIdoBal = await ido.balanceOf(contract.address);
        // console.log(votingIdoBal.toString());
        await increase(duration.days(10));
        await contract.connect(alice).endReviewVote(1, 0); // improve tests for revert
        const review = await contract.connect(alice).getReview(1, 0);

        // console.log(review);
        // console.log(proposal2);

        let carolBalance = await ido.balanceOf(carol.address);
        // console.log(carolBalance.toString());
        votingIdoBal = await ido.balanceOf(contract.address);
        // console.log("IDO Contract blanace:", votingIdoBal.toString());

        const proposal = await contract.connect(alice).getProposal(1);

        // console.log(proposal);
      });
    });
  });
});
