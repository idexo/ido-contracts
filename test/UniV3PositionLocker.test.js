const { expect } = require("chai");  
const { ethers } = require("hardhat");  
const { constants } = require("@openzeppelin/test-helpers");  
  
// Mock for INonfungiblePositionManager  
const MockPositionManagerArtifact = {  
  abi: [  
    "function positions(uint256) view returns (tuple(uint96 nonce, address operator, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1))",  
    "function collect(tuple(uint256 tokenId, address recipient, uint128 amount0Max, uint128 amount1Max)) payable returns (uint256, uint256)",  
    "function transferFrom(address, address, uint256)",  
    "function safeTransferFrom(address, address, uint256)",  
    "function approve(address, uint256)",  
    "function getApproved(uint256) view returns (address)",  
    "function isApprovedForAll(address, address) view returns (bool)",  
    "function setApprovalForAll(address, bool)",  
    "function ownerOf(uint256) view returns (address)"  
  ],  
  bytecode: "0x"  
};  
  
describe("UniV3PositionLocker", function () {  
  let positionLocker;  
  let mockPositionManager;  
  let owner;  
  let user1;  
  let user2;  
  let lockDuration = 30 * 24 * 60 * 60; // 30 days in seconds  
  let tokenId = 12345;  
    
  // Sample position data  
  const samplePosition = {  
    nonce: 1,  
    operator: constants.ZERO_ADDRESS,  
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
    
  // Custom time manipulation function (without hardhat-network-helpers)  
  async function increaseTime(seconds) {  
    await ethers.provider.send("evm_increaseTime", [seconds]);  
    await ethers.provider.send("evm_mine");  
  }  
    
  beforeEach(async function () {  
    [owner, user1, user2] = await ethers.getSigners();  
      
    // Deploy mock position manager  
    const MockPositionManager = await ethers.getContractFactory(  
      "MockPositionManager",  
      {  
        signer: owner  
      }  
    );  
      
    mockPositionManager = await MockPositionManager.deploy();  
    await mockPositionManager.deployed();  
      
    // Set up mock methods  
    await mockPositionManager.setPosition(tokenId, samplePosition);  
    await mockPositionManager.setOwner(tokenId, user1.address);  
      
    // Deploy the locker contract  
    const UniV3PositionLocker = await ethers.getContractFactory(  
      "UniV3PositionLocker"  
    );  
    positionLocker = await UniV3PositionLocker.deploy(  
      mockPositionManager.address,  
      lockDuration  
    );  
    await positionLocker.deployed();  
      
    // Approve token for transfer  
    await mockPositionManager.connect(user1).setApprovalForAll(positionLocker.address, true);  
  });  
    
  describe("Deployment", function () {  
    it("Should set the correct position manager address", async function () {  
      expect(await positionLocker.positionManager()).to.equal(  
        mockPositionManager.address  
      );  
    });  
      
    it("Should set the correct lock duration", async function () {  
      expect(await positionLocker.lockDuration()).to.equal(lockDuration);  
    });  
      
    it("Should set the correct lock end timestamp", async function () {  
      const deploymentTime = await positionLocker.deploymentTime();  
      const lockEndTimestamp = await positionLocker.lockEndTimestamp();  
      expect(lockEndTimestamp).to.equal(  
        deploymentTime.add(lockDuration)  
      );  
    });  
  });  
    
  describe("Locking Positions", function () {  
    it("Should lock a position successfully", async function () {  
      await mockPositionManager.connect(user1).approve(positionLocker.address, tokenId);  
        
      const lockTx = await positionLocker.connect(user1).lockPosition(tokenId);  
      const receipt = await lockTx.wait();  
        
      // Check for event emission  
      const event = receipt.events?.find(e => e.event === "PositionLocked");  
      expect(event).to.not.be.undefined;  
      expect(event.args.tokenId).to.equal(tokenId);  
      expect(event.args.owner).to.equal(user1.address);  
        
      // Get the lock ID from the event  
      const lockId = event.args.lockId;  
        
      // Check stored locked position  
      const lockedPosition = await positionLocker.getLockedPosition(lockId);  
      expect(lockedPosition.owner).to.equal(user1.address);  
      expect(lockedPosition.tokenId).to.equal(tokenId);  
      expect(lockedPosition.isWithdrawn).to.be.false;  
        
      // Check token ID to lock ID mapping  
      expect(await positionLocker.getLockIdForToken(tokenId)).to.equal(lockId);  
    });  
      
    it("Should revert when trying to lock an already locked position", async function () {  
      await positionLocker.connect(user1).lockPosition(tokenId);  
        
      await expect(  
        positionLocker.connect(user1).lockPosition(tokenId)  
      ).to.be.revertedWith("Token already locked");  
    });  
      
    it("Should revert when trying to lock an invalid token ID", async function () {  
      await expect(  
        positionLocker.connect(user1).lockPosition(0)  
      ).to.be.revertedWith("Invalid token ID");  
    });  
  });  
    
  describe("Collecting Fees", function () {  
    let lockId;  
      
    beforeEach(async function () {  
      // Lock a position first to get a lock ID  
      const lockTx = await positionLocker.connect(user1).lockPosition(tokenId);  
      const receipt = await lockTx.wait();  
      const event = receipt.events?.find(e => e.event === "PositionLocked");  
      lockId = event.args.lockId;  
        
      // Setup mock collect method  
      await mockPositionManager.setCollectAmounts(  
        ethers.utils.parseUnits("0.1", 18),  
        ethers.utils.parseUnits("0.05", 18)  
      );  
    });  
      
    it("Should collect fees successfully", async function () {  
      const collectTx = await positionLocker.connect(user1).collectFees(  
        lockId,  
        user1.address,  
        ethers.constants.MaxUint128,  
        ethers.constants.MaxUint128  
      );  
        
      const receipt = await collectTx.wait();  
        
      // Check for event emission  
      const event = receipt.events?.find(e => e.event === "FeesCollected");  
      expect(event).to.not.be.undefined;  
      expect(event.args.lockId).to.equal(lockId);  
      expect(event.args.tokenId).to.equal(tokenId);  
      expect(event.args.recipient).to.equal(user1.address);  
      expect(event.args.amount0).to.equal(ethers.utils.parseUnits("0.1", 18));  
      expect(event.args.amount1).to.equal(ethers.utils.parseUnits("0.05", 18));  
    });  
      
    it("Should revert when non-owner tries to collect fees", async function () {  
      await expect(  
        positionLocker.connect(user2).collectFees(  
          lockId,  
          user2.address,  
          ethers.constants.MaxUint128,  
          ethers.constants.MaxUint128  
        )  
      ).to.be.revertedWith("Not the position owner");  
    });  
      
    it("Should revert when collecting to zero address", async function () {  
      await expect(  
        positionLocker.connect(user1).collectFees(  
          lockId,  
          constants.ZERO_ADDRESS,  
          ethers.constants.MaxUint128,  
          ethers.constants.MaxUint128  
        )  
      ).to.be.revertedWith("Invalid recipient");  
    });  
      
    it("Should revert when position is already withdrawn", async function () {  
      // Fast forward to end of lock period  
      await increaseTime(lockDuration + 1);  
        
      // Unlock the position  
      await positionLocker.connect(user1).unlockPosition(lockId);  
        
      // Try to collect fees  
      await expect(  
        positionLocker.connect(user1).collectFees(  
          lockId,  
          user1.address,  
          ethers.constants.MaxUint128,  
          ethers.constants.MaxUint128  
        )  
      ).to.be.revertedWith("Position already withdrawn");  
    });  
  });  
    
  describe("Unlocking Positions", function () {  
    let lockId;  
      
    beforeEach(async function () {  
      // Lock a position first to get a lock ID  
      const lockTx = await positionLocker.connect(user1).lockPosition(tokenId);  
      const receipt = await lockTx.wait();  
      const event = receipt.events?.find(e => e.event === "PositionLocked");  
      lockId = event.args.lockId;  
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
        
      // Check for event emission  
      const event = receipt.events?.find(e => e.event === "PositionUnlocked");  
      expect(event).to.not.be.undefined;  
      expect(event.args.lockId).to.equal(lockId);  
      expect(event.args.tokenId).to.equal(tokenId);  
      expect(event.args.recipient).to.equal(user1.address);  
        
      // Check locked position is marked as withdrawn  
      const lockedPosition = await positionLocker.getLockedPosition(lockId);  
      expect(lockedPosition.isWithdrawn).to.be.true;  
    });  
      
    it("Should revert when non-owner tries to unlock", async function () {  
      // Fast forward to end of lock period  
      await increaseTime(lockDuration + 1);  
        
      await expect(  
        positionLocker.connect(user2).unlockPosition(lockId)  
      ).to.be.revertedWith("Not the position owner");  
    });  
      
    it("Should revert when position is already withdrawn", async function () {  
      // Fast forward to end of lock period  
      await increaseTime(lockDuration + 1);  
        
      // Unlock once  
      await positionLocker.connect(user1).unlockPosition(lockId);  
        
      // Try to unlock again  
      await expect(  
        positionLocker.connect(user1).unlockPosition(lockId)  
      ).to.be.revertedWith("Position already withdrawn");  
    });  
  });  
    
  describe("View Functions", function () {  
    let lockId;  
      
    beforeEach(async function () {  
      // Lock a position first to get a lock ID  
      const lockTx = await positionLocker.connect(user1).lockPosition(tokenId);  
      const receipt = await lockTx.wait();  
      const event = receipt.events?.find(e => e.event === "PositionLocked");  
      lockId = event.args.lockId;  
    });  
      
    it("Should return correct position details", async function () {  
      const position = await positionLocker.getPositionDetails(tokenId);  
        
      expect(position.token0).to.equal(samplePosition.token0);  
      expect(position.token1).to.equal(samplePosition.token1);  
      expect(position.fee).to.equal(samplePosition.fee);  
      expect(position.tickLower).to.equal(samplePosition.tickLower);  
      expect(position.tickUpper).to.equal(samplePosition.tickUpper);  
      expect(position.liquidity).to.equal(samplePosition.liquidity);  
      expect(position.feeGrowthInside0LastX128).to.equal(samplePosition.feeGrowthInside0LastX128);  
      expect(position.feeGrowthInside1LastX128).to.equal(samplePosition.feeGrowthInside1LastX128);  
      expect(position.tokensOwed0).to.equal(samplePosition.tokensOwed0);  
      expect(position.tokensOwed1).to.equal(samplePosition.tokensOwed1);  
    });  
      
    it("Should return correct locked position info", async function () {  
      const lockedPosition = await positionLocker.getLockedPosition(lockId);  
        
      expect(lockedPosition.owner).to.equal(user1.address);  
      expect(lockedPosition.tokenId).to.equal(tokenId);  
      expect(lockedPosition.isWithdrawn).to.be.false;  
    });  
      
    it("Should return correct lock ID for token ID", async function () {  
      expect(await positionLocker.getLockIdForToken(tokenId)).to.equal(lockId);  
    });  
      
    it("Should return correct remaining lock time", async function () {  
      const initialRemainingTime = await positionLocker.getRemainingLockTime();  
      expect(initialRemainingTime).to.be.closeTo(  
        ethers.BigNumber.from(lockDuration),  
        60 // allow for small discrepancy due to block timing  
      );  
        
      // Fast forward half the lock period  
      await increaseTime(lockDuration / 2);  
        
      const halfwayRemainingTime = await positionLocker.getRemainingLockTime();  
      expect(halfwayRemainingTime).to.be.closeTo(  
        ethers.BigNumber.from(lockDuration / 2),  
        60 // allow for small discrepancy due to block timing  
      );  
        
      // Fast forward past the lock period  
      await increaseTime(lockDuration);  
        
      const finalRemainingTime = await positionLocker.getRemainingLockTime();  
      expect(finalRemainingTime).to.equal(0);  
    });  
  });  
    
  describe("ERC721 Receiver", function () {  
    it("Should implement onERC721Received correctly", async function () {  
      const selector = await positionLocker.onERC721Received(  
        constants.ZERO_ADDRESS,  
        constants.ZERO_ADDRESS,  
        0,  
        "0x"  
      );  
        
      const expectedSelector = "0x150b7a02"; // bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))  
      expect(selector.slice(0, 10)).to.equal(expectedSelector);  
    });  
  });  
});