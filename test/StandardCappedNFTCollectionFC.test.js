// test/StandardCappedNFTCollection.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { expectRevert, expectEvent } = require("@openzeppelin/test-helpers");

describe("StandardCappedNFTCollectionFC", function () {
  let NFT, nftContract, owner, addr1, addr2, cap;

  beforeEach(async () => {
    cap = 10;
    NFT = await ethers.getContractFactory("StandardCappedNFTCollectionFC");
    [owner, addr1, addr2, _] = await ethers.getSigners();
    nftContract = await NFT.deploy("TestNFT", "TNFT", "https://example.com/", cap, owner.address, owner.address);
    await nftContract.deployed();
  });

  describe("Deployment", function () {
    it("Should set the correct cap", async function () {
      expect(await nftContract.tokenIds()).to.equal(0);
      expect(await nftContract.baseURI()).to.equal("https://example.com/");
    });
  });

  describe("Minting", function () {
    it("Should mint an NFT to addr1 with correct URI", async function () {
      const mintTransaction = await nftContract.mintNFT(addr1.address, "token1");
      const receipt = await mintTransaction.wait();
      const tokenId = receipt.events.filter((event) => event.event === "NFTCreated")[0].args.nftId;

      expect(await nftContract.ownerOf(tokenId)).to.equal(addr1.address);
      expect(await nftContract.tokenURI(tokenId)).to.equal("https://example.com/token1");
    });

    it("Should mint multiple NFTs with correct URIs", async function () {
      const recipients = [addr1.address, addr2.address];
      const tokenURIs = ["token1", "token2"];

      const mintTransaction = await nftContract.mintBatchNFT(recipients, tokenURIs);
      const receipt = await mintTransaction.wait();

      const events = receipt.events.filter((event) => event.event === "NFTCreated");

      for (let i = 0; i < recipients.length; i++) {
        const tokenId = events[i].args.nftId;
        expect(await nftContract.ownerOf(tokenId)).to.equal(recipients[i]);
        expect(await nftContract.tokenURI(tokenId)).to.equal(`https://example.com/${tokenURIs[i]}`);
      }
    });


    it("Should not allow minting more NFTs than the cap", async function () {
      const tokenURIs = Array(cap + 1).fill("token");
      const recipients = Array(cap + 1).fill(addr1.address);

      await expect(nftContract.mintBatchNFT(recipients, tokenURIs)).to.be.revertedWith("StandardCappedNFTCollection#mintBatchNFT: CANNOT_EXCEED_MINTING_CAP");
    });
  })

 describe("Transfers", function () {
    it("Should transfer NFT from addr1 to addr2", async function () {
      const mintTransaction = await nftContract.mintNFT(addr1.address, "token1");
      const receipt = await mintTransaction.wait();
      const tokenId = receipt.events.filter((event) => event.event === "NFTCreated")[0].args.nftId;

      const tx = await nftContract.connect(addr1).transferFrom(addr1.address, addr2.address, tokenId);
      await tx.wait();

      expect(await nftContract.ownerOf(tokenId)).to.equal(addr2.address);
    });

    it("Should not allow transferring NFT to zero address", async function () {
      const mintTransaction = await nftContract.mintNFT(addr1.address, "token1");
      const receipt = await mintTransaction.wait();
      const tokenId = receipt.events.filter((event) => event.event === "NFTCreated")[0].args.nftId;

      await expectRevert(
        nftContract.connect(addr1).transferFrom(addr1.address, ethers.constants.AddressZero, tokenId),
        "CommunityNFT#_transfer: TRANSFER_TO_THE_ZERO_ADDRESS"
      );
    });
  });




    describe("Description", function () {
      it("Should add collection description", async function () {
      const description = "This is a test collection";
      await nftContract.addDescription(description);
      expect(await nftContract.collectionDescription()).to.equal(description);
      });
      });

    describe("URI", function () {
    it("Should set token URI correctly", async function () {
      const mintTransaction = await nftContract.mintNFT(addr1.address, "token1");
      const receipt = await mintTransaction.wait();
      const tokenId = receipt.events.filter((event) => event.event === "NFTCreated")[0].args.nftId;

      const newTokenURI = "newTokenURI";
      await nftContract.setTokenURI(tokenId, newTokenURI);

      expect(await nftContract.tokenURI(tokenId)).to.equal(`https://example.com/${newTokenURI}`);
    });

    it("Should only allow operator to set token URI", async function () {
      const mintTransaction = await nftContract.mintNFT(addr1.address, "token1");
      const receipt = await mintTransaction.wait();
      const tokenId = receipt.events.filter((event) => event.event === "NFTCreated")[0].args.nftId;

      const nonOperator = nftContract.connect(addr2);
      const newTokenURI = "newTokenURI";

      await expectRevert(
        nonOperator.setTokenURI(tokenId, newTokenURI),
        "Operatorable: CALLER_NO_OPERATOR_ROLE"
      );
    });

    
});


    describe("Holder", function () {
      it("Should return true if address owns any NFTs in the collection", async function () {
      const tokenURI = "token1";
      await nftContract.mintNFT(addr1.address, tokenURI);
      expect(await nftContract.isHolder(addr1.address)).to.equal(true);
      });

      it("Should return false if address does not own any NFTs in the collection", async function () {
      expect(await nftContract.isHolder(addr1.address)).to.equal(false);
      });

      });

     describe("Minting Cap", function () {
      it("Should not allow minting more NFTs than the cap", async function () {
        for (let i = 0; i < cap; i++) {
          await nftContract.mintNFT(addr1.address, `token${i}`);
        }

        await expectRevert(
          nftContract.mintNFT(addr1.address, "tokenExceedCap"),
          "StandardCappedNFTCollection#_mint: CANNOT_EXCEED_MINTING_CAP"
        );
      });
    });

 describe("Operator Role", function () {
    it("Should only allow operator to mint NFTs", async function () {
      const nonOperator = nftContract.connect(addr2);

      await expectRevert(
        nonOperator.mintNFT(addr1.address, "token1"),
        "Operatorable: CALLER_NO_OPERATOR_ROLE"
      );
    });

    it("Should only allow operator to add description", async function () {
      const nonOperator = nftContract.connect(addr2);

      await expectRevert(
        nonOperator.addDescription("This is a new description"),
        "Operatorable: CALLER_NO_OPERATOR_ROLE"
      );
    });
});


  describe("Owner Role", function () {
    it("Should not allow non-owner to set base URI", async function () {
      const nftContractWithAddr1 = nftContract.connect(addr1);
      await expect(nftContractWithAddr1.setBaseURI("https://newexample.com/")).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Token Count", function () {
    it("Should correctly update the tokenIds count after minting", async function () {
      await nftContract.mintNFT(addr1.address, "token1");
      expect(await nftContract.tokenIds()).to.equal(1);

      await nftContract.mintNFT(addr1.address, "token2");
      expect(await nftContract.tokenIds()).to.equal(2);
    });
  });
})


