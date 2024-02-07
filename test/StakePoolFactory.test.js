// SPDX-License-Identifier: MIT
const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const { BigNumber } = require("ethers");
const { time } = require('@openzeppelin/test-helpers');
const ERC20 = artifacts.require("ERC20Mock")

const zeroAddress = "0x0000000000000000000000000000000000000000";

describe("StakePoolFactory", function () {
  let StakePoolFactory, StakePoolFlexLockFC, stakePoolFactory, stakePoolFlexLockFC;
  let depositToken, rewardToken, admin, operator, creator;

  before(async function () {
    [creator, admin, operator] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20");
    depositToken = await ERC20.deploy("Test Token", "TT");
    rewardToken = await ERC20.deploy("Test Token", "TT");

    StakePoolFactory = await ethers.getContractFactory("StakePoolFactory");
    StakePoolFlexLockFC = await ethers.getContractFactory("StakePoolFlexLockFC");
  });

  beforeEach(async function () {
    stakePoolFactory = await StakePoolFactory.deploy();
  });

  it("should create StakePoolFlexLockFC instance and emit event", async function () {
    const collectionName = "Test Collection";
    const collectionSymbol = "TCS";
    const collectionBaseURI = "https://example.com/metadata/";
    const minStakeAmount = BigNumber.from(1000);

    const creationTx = await stakePoolFactory.createStakePoolFlexLock(
    collectionName,
    collectionSymbol,
    collectionBaseURI,
    minStakeAmount,
    depositToken.address,
    rewardToken.address,
    admin.address,
    operator.address
  );

  const creationTxReceipt = await creationTx.wait();
  const event = creationTxReceipt.events.find(event => event.event === "StakePoolFlexLockCreated");
  const newInstanceAddress = event.args.instance;

  await expect(creationTx).to.emit(stakePoolFactory, "StakePoolFlexLockCreated")
    .withArgs(creator.address, newInstanceAddress);


    const eventFilter = stakePoolFactory.filters.StakePoolFlexLockCreated(creator.address);
    const events = await stakePoolFactory.queryFilter(eventFilter);
    const stakePoolFlexLockFCAddress = events[0].args.instance;

    stakePoolFlexLockFC = StakePoolFlexLockFC.connect(creator).attach(stakePoolFlexLockFCAddress);
    await stakePoolFlexLockFC.acceptOwnership();
    expect(await stakePoolFlexLockFC.name()).to.equal(collectionName);
    expect(await stakePoolFlexLockFC.symbol()).to.equal(collectionSymbol);
    expect(await stakePoolFlexLockFC.baseURI()).to.equal(collectionBaseURI);
    expect(await stakePoolFlexLockFC.minStakeAmount()).to.equal(minStakeAmount);
    expect(await stakePoolFlexLockFC.owner()).to.equal(creator.address);
  });

  
});