// SPDX-License-Identifier: MIT
const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const { BigNumber } = require("ethers");
const { time } = require('@openzeppelin/test-helpers');

const zeroAddress = "0x0000000000000000000000000000000000000000";

describe("NFTCollectionCappedFactory", function () {
  let NFTCollectionCappedFactory, StakePoolFlexLockFC, nftCollectionCappedFactory, standardCappedNFTCollectionFC;
  let depositToken, rewardToken, admin, operator, creator;

  before(async function () {
    [creator, admin, operator] = await ethers.getSigners();


    NFTCollectionCappedFactory = await ethers.getContractFactory("NFTCollectionCappedFactory");
    StandardCappedNFTCollectionFC = await ethers.getContractFactory("StandardCappedNFTCollectionFC");
  });

  beforeEach(async function () {
    NFTCollectionCappedFactory = await NFTCollectionCappedFactory.deploy();
  });

  it("should create StandardCappedNFTCollectionFC instance and emit event", async function () {
    const collectionName = "Test Collection";
    const collectionSymbol = "TCS";
    const collectionBaseURI = "https://example.com/metadata/";
    const cap = 100;

    const creationTx = await NFTCollectionCappedFactory.createStandardCappedNFTCollection(
    collectionName,
    collectionSymbol,
    collectionBaseURI,
    cap,
    admin.address,
    operator.address
  );

  const creationTxReceipt = await creationTx.wait();
  const event = creationTxReceipt.events.find(event => event.event === "StandardCappedNFTCollection");
  const newInstanceAddress = event.args.instance;

  await expect(creationTx).to.emit(NFTCollectionCappedFactory, "StandardCappedNFTCollection")
    .withArgs(creator.address, newInstanceAddress);


    const eventFilter = NFTCollectionCappedFactory.filters.StandardCappedNFTCollection(creator.address);
    const events = await NFTCollectionCappedFactory.queryFilter(eventFilter);
    const standardCappedNFTCollectionFCAddress = events[0].args.instance;

    standardCappedNFTCollectionFC = StandardCappedNFTCollectionFC.connect(creator).attach(standardCappedNFTCollectionFCAddress);
    await standardCappedNFTCollectionFC.acceptOwnership();
    expect(await standardCappedNFTCollectionFC.name()).to.equal(collectionName);
    expect(await standardCappedNFTCollectionFC.symbol()).to.equal(collectionSymbol);
    expect(await standardCappedNFTCollectionFC.baseURI()).to.equal(collectionBaseURI);
    expect(await standardCappedNFTCollectionFC.owner()).to.equal(creator.address);
  });

  
});