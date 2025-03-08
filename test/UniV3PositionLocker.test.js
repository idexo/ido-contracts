const { expect } = require("chai");  
const { ethers } = require("hardhat");  
  
describe("UniV3PositionLocker", function () {  
  let positionLocker;  
  let mockPositionManager;  
  let owner, user1, user2;  
  let tokenId = 12345;  
  let lockDuration = 30 * 24 * 60 * 60; // 30 days in seconds  
    
  // Sample position data  
  const samplePosition = {  
    nonce: 1,  
    operator: ethers.constants.AddressZero,  
    token0: "0x6B175474E89094C44Da98b954EedeAC495271d0F", // DAI  
    token1: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH  
    fee: 3000, // 0.3%  
    tickLower: -10000,  
    tickUpper: 10000,  
    liquidity: ethers.utils.parseUnits("1", 18),  
    feeGrowthInside0LastX128: ethers.utils.parseUnits("10", 18),  
    feeGrowthInside1LastX128: ethers.utils.parseUnits("5", 18),  
    tokensOwed0: ethers.utils.parseUnits("0.2", 18),  
    tokensOwed1: ethers.utils.parseUnits("0.1", 18)  
  };  
    
  // Helper function to increase time  
  async function increaseTime(seconds) {  
    await ethers.provider.send("evm_increaseTime", [seconds]);  
    await ethers.provider.send("evm_mine");  
  }  
    
  beforeEach(async function () {  
    [owner, user1, user2] = await ethers.getSigners();  
      
    // Deploy mock position manager  
    const MockPositionManager = await ethers.getContractFactory("MockPositionManager");  
    mockPositionManager = await MockPositionManager.deploy();  
    await mockPositionManager.deployed();  
      
    // Setup mock position and ownership  
    await mockPositionManager.setPosition(tokenId, samplePosition);  
    await mockPositionManager.setOwner(tokenId, user1.address);  
      
    // Set collect amounts for tests  
    await mockPositionManager.setCollectAmounts(  
      ethers.utils.parseUnits("0.1", 18),  
      ethers.utils.parseUnits("0.05", 18)  
    );  
      
    // Deploy the locker contract  
    const UniV3PositionLocker = await ethers.getContractFactory("UniV3PositionLocker");  
    positionLocker = await UniV3PositionLocker.deploy(  
      mockPositionManager.address,  
      lockDuration  
    );  
    await positionLocker.deployed();  
      
    // Approve the locker to transfer the NFT  
    await mockPositionManager.connect(user1).setApprovalForAll(positionLocker.address, true);  
  });  
    
  describe("Contract Deployment", function () {  
    it("Should set the correct position manager address", async function () {  
      expect(await positionLocker.positionManager()).to.equal(mockPositionManager.address);  
    });  
      
    it("Should set the correct lock duration", async function () {  
      expect(await positionLocker.lockDuration()).to.equal(lockDuration);  
    });  
      
    it("Should calculate the correct lock end timestamp", async function () {  
      const deployTime = await positionLocker.deploymentTime();  
      const endTime = await positionLocker.lockEndTimestamp();  
      expect(endTime.sub(deployTime)).to.equal(lockDuration);  
    });  
  });  
    
  describe("Locking Positions", function () {  
    it("Should lock a position correctly", async function () {  
      const lockTx = await positionLocker.connect(user1).lockPosition(tokenId);  
      const receipt = await lockTx.wait();  
        
      // Check event emission  
      const event = receipt.events.find(e => e.event === "PositionLocked");  
      expect(event).to.not.be.undefined;  
        
      const lockId = event.args.lockId;  
      expect(event.args.tokenId).to.equal(tokenId);  
      expect(event.args.owner).to.equal(user1.address);  
        
      // Check stored data  
      const position = await positionLocker.getLockedPosition(lockId);  
      expect(position.owner).to.equal(user1.address);  
      expect(position.tokenId).to.equal(tokenId);  
      expect(position.isWithdrawn).to.be.false;  
        
      // Check NFT was transferred  
      expect(await mockPositionManager.ownerOf(tokenId)).to.equal(positionLocker.address);  
    });  
      
    it("Should revert when trying to lock an already locked position", async function () {  
      await positionLocker.connect(user1).lockPosition(tokenId);  
      await expect(  
        positionLocker.connect(user1).lockPosition(tokenId)  
      ).to.be.revertedWith("Token already locked");  
    });  
  });  
    
  describe("Position Details", function () {  
    let lockId;  
      
    beforeEach(async function () {  
      const lockTx = await positionLocker.connect(user1).lockPosition(tokenId);  
      const receipt = await lockTx.wait();  
      lockId = receipt.events.find(e => e.event === "PositionLocked").args.lockId;  
    });  
      
    it("Should return correct position details", async function () {  
      const details = await positionLocker.getPositionDetails(tokenId);  
        
      expect(details.token0).to.equal(samplePosition.token0);  
      expect(details.token1).to.equal(samplePosition.token1);  
      expect(details.fee).to.equal(samplePosition.fee);  
      expect(details.tickLower).to.equal(samplePosition.tickLower);  
      expect(details.tickUpper).to.equal(samplePosition.tickUpper);  
      expect(details.liquidity).to.equal(samplePosition.liquidity);  
      expect(details.feeGrowthInside0LastX128).to.equal(samplePosition.feeGrowthInside0LastX128);  
      expect(details.feeGrowthInside1LastX128).to.equal(samplePosition.feeGrowthInside1LastX128);  
      expect(details.tokensOwed0).to.equal(samplePosition.tokensOwed0);  
      expect(details.tokensOwed1).to.equal(samplePosition.tokensOwed1);  
    });  
      
    it("Should retrieve correct lock ID for a token ID", async function () {  
      const retrievedLockId = await positionLocker.getLockIdForToken(tokenId);  
      expect(retrievedLockId).to.equal(lockId);  
    });  
  });  
    
  describe("Unlocking Positions", function () {  
    let lockId;  
      
    beforeEach(async function () {  
      const lockTx = await positionLocker.connect(user1).lockPosition(tokenId);  
      const receipt = await lockTx.wait();  
      lockId = receipt.events.find(e => e.event === "PositionLocked").args.lockId;  
    });  
      
    it("Should revert when trying to unlock before lock period ends", async function () {  
      await expect(  
        positionLocker.connect(user1).unlockPosition(lockId)  
      ).to.be.revertedWith("Lock period not ended yet");  
    });  
      
    it("Should unlock a position after lock period ends", async function () {  
      // Fast forward to end of lock period  
      await increaseTime(lockDuration + 1);  
        
      const unlockTx = await positionLocker.connect(user1).unlockPosition(lockId);  
      const receipt = await unlockTx.wait();  
        
      // Check event emission  
      const event = receipt.events.find(e => e.event === "PositionUnlocked");  
      expect(event).to.not.be.undefined;  
      expect(event.args.lockId).to.equal(lockId);  
      expect(event.args.tokenId).to.equal(tokenId);  
      expect(event.args.recipient).to.equal(user1.address);  
        
      // Check position is marked as withdrawn  
      const position = await positionLocker.getLockedPosition(lockId);  
      expect(position.isWithdrawn).to.be.true;  
        
      // Check NFT was transferred back  
      expect(await mockPositionManager.ownerOf(tokenId)).to.equal(user1.address);  
    });  
      
    it("Should revert when non-owner tries to unlock", async function () {  
      await increaseTime(lockDuration + 1);  
        
      await expect(  
        positionLocker.connect(user2).unlockPosition(lockId)  
      ).to.be.revertedWith("Not the position owner");  
    });  
      
    it("Should revert when position is already withdrawn", async function () {  
      await increaseTime(lockDuration + 1);  
        
      await positionLocker.connect(user1).unlockPosition(lockId);  
        
      await expect(  
        positionLocker.connect(user1).unlockPosition(lockId)  
      ).to.be.revertedWith("Position already withdrawn");  
    });  
  });  
    
  describe("Lock Time Information", function() {  
    it("Should return correct remaining lock time", async function () {  
      const initialTime = await positionLocker.getRemainingLockTime();  
      expect(initialTime).to.be.closeTo(  
        ethers.BigNumber.from(lockDuration),  
        60 // allow for small discrepancy due to block timing  
      );  
        
      await increaseTime(lockDuration / 2);  
        
      const halfwayTime = await positionLocker.getRemainingLockTime();  
      expect(halfwayTime).to.be.closeTo(  
        ethers.BigNumber.from(lockDuration / 2),  
        60 // allow for small discrepancy  
      );  
        
      await increaseTime(lockDuration);  
        
      const finalTime = await positionLocker.getRemainingLockTime();  
      expect(finalTime).to.equal(0);  
    });  
  });  
    
  describe("ERC721 Receiver", function () {  
    it("Should implement onERC721Received correctly", async function () {  
      const selector = await positionLocker.onERC721Received(  
        ethers.constants.AddressZero,  
        ethers.constants.AddressZero,  
        0,  
        "0x"  
      );  
        
      expect(selector).to.equal("0x150b7a02");  
    });  
  });  
}); 