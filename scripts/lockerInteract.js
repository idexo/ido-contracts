const { ethers } = require("hardhat");  
const yargs = require("yargs/yargs");  
  
const argv = yargs()  
  .option('address', {  
    alias: 'a',  
    description: 'Locker contract address',  
    type: 'string'  
  })  
  .option('position', {  
    alias: 'p',  
    description: 'Position ID to interact with',  
    type: 'string'  
  })  
  .option('command', {  
    alias: 'c',  
    description: 'Command to execute: info, approve, lock, collect, unlock, position-details, check-approval',  
    type: 'string',  
    default: 'info'  
  })  
  .option('recipient', {  
    alias: 'r',  
    description: 'Recipient address for collect fees',  
    type: 'string'  
  })  
  .option('max0', {  
    alias: 'm0',  
    description: 'Max amount of token0 to collect',  
    type: 'string',  
    default: '340282366920938463463374607431768211455' // uint128 max by default  
  })  
  .option('max1', {  
    alias: 'm1',  
    description: 'Max amount of token1 to collect',  
    type: 'string',  
    default: '340282366920938463463374607431768211455' // uint128 max by default  
  })  
  .option('lockid', {  
    alias: 'l',  
    description: 'Lock ID for operations',  
    type: 'string'  
  })  
  .option('debug', {  
    alias: 'd',  
    description: 'Show debug information',  
    type: 'boolean',  
    default: false  
  })  
  .help()  
  .alias('help', 'h')  
  .argv;  
  
async function main() {  
  // Get the deployed contract address from arguments or env  
  const LOCKER_ADDRESS = argv.address || process.env.LOCKER_ADDRESS;  
  if (!LOCKER_ADDRESS) {  
    console.error("Please provide a locker contract address with --address or LOCKER_ADDRESS env var");  
    return;  
  }  
  
  console.log(`Interacting with UniV3PositionLocker at ${LOCKER_ADDRESS}`);  
      
  // Get contract instance  
  const locker = await ethers.getContractAt("UniV3PositionLocker", LOCKER_ADDRESS);  
      
  // Get the position manager address from the locker  
  const positionManagerAddress = await locker.positionManager();  
  console.log(`Position Manager: ${positionManagerAddress}`);  
      
  // Get the position manager contract  
  const positionManager = await ethers.getContractAt("INonfungiblePositionManager", positionManagerAddress);  
      
  // Get the signer  
  const [signer] = await ethers.getSigners();  
  console.log(`Connected with: ${signer.address}`);  
    
  // Execute the specific command  
  const command = argv.command || 'info';  
      
  try {  
    switch (command) {  
      case 'info':  
        await showInfo(locker, positionManager);  
        break;  
      case 'approve':  
        await approvePosition(positionManager, LOCKER_ADDRESS, argv.position);  
        break;  
      case 'check-approval':  
        await checkApproval(positionManager, LOCKER_ADDRESS, argv.position, signer.address);  
        break;  
      case 'lock':  
        await lockPosition(locker, argv.position);  
        break;  
      case 'collect':  
        await collectFees(locker, argv.lockid, argv.recipient || signer.address, argv.max0, argv.max1);  
        break;  
      case 'unlock':  
        await unlockPosition(locker, argv.lockid);  
        break;  
      case 'position-details':  
        await getPositionDetails(locker, argv.position);  
        break;  
      default:  
        console.log(`Unknown command: ${command}`);  
        console.log("Available commands: info, approve, check-approval, lock, collect, unlock, position-details");  
    }  
  } catch (error) {  
    console.error("Error executing command:", error);  
    if (argv.debug) {  
      console.error(error);  
    }  
  }  
}  
  
async function showInfo(locker, positionManager) {  
  // Get general contract info  
  const lockDuration = await locker.lockDuration();  
  const lockEndTimestamp = await locker.lockEndTimestamp();  
  const remainingLockTime = await locker.getRemainingLockTime();  
      
  console.log(`\n=== Contract Information ===`);  
  console.log(`Lock Duration: ${lockDuration.toString()} seconds (${Math.floor(lockDuration / 86400)} days)`);  
  console.log(`Lock End Timestamp: ${new Date(lockEndTimestamp.toNumber() * 1000).toISOString()}`);  
  console.log(`Remaining Lock Time: ${remainingLockTime.toString()} seconds (${Math.floor(remainingLockTime / 86400)} days, ${Math.floor((remainingLockTime % 86400) / 3600)} hours)`);  
      
  console.log(`\n=== Usage Instructions ===`);  
  console.log(`1. Check approval:    npx hardhat run scripts/interact-locker.js --network mainnet --address ${locker.address} --position POSITION_ID --command check-approval`);  
  console.log(`2. Approve position:  npx hardhat run scripts/interact-locker.js --network mainnet --address ${locker.address} --position POSITION_ID --command approve`);  
  console.log(`3. Lock position:     npx hardhat run scripts/interact-locker.js --network mainnet --address ${locker.address} --position POSITION_ID --command lock`);  
  console.log(`4. Collect fees:      npx hardhat run scripts/interact-locker.js --network mainnet --address ${locker.address} --lockid LOCK_ID --command collect --recipient RECIPIENT_ADDRESS`);  
  console.log(`5. Unlock position:   npx hardhat run scripts/interact-locker.js --network mainnet --address ${locker.address} --lockid LOCK_ID --command unlock`);  
  console.log(`6. Position details:  npx hardhat run scripts/interact-locker.js --network mainnet --address ${locker.address} --position POSITION_ID --command position-details`);  
}  
  
async function checkApproval(positionManager, lockerAddress, tokenId, ownerAddress) {  
  if (!tokenId) {  
    console.error("Please provide a position ID");  
    return;  
  }  
      
  try {  
    // Check direct approval  
    const approvedAddress = await positionManager.getApproved(tokenId);  
    const isApprovedForAll = await positionManager.isApprovedForAll(ownerAddress, lockerAddress);  
        
    console.log(`\n=== Approval Status for Position #${tokenId} ===`);  
    console.log(`Direct Approval: ${approvedAddress}`);  
    console.log(`Is Approved For All: ${isApprovedForAll}`);  
        
    if (approvedAddress.toLowerCase() === lockerAddress.toLowerCase() || isApprovedForAll) {  
      console.log(`✅ Position #${tokenId} is approved for the locker contract`);  
    } else {  
      console.log(`❌ Position #${tokenId} is NOT approved for the locker contract`);  
      console.log(`Run the approve command to grant approval.`);  
    }  
  } catch (error) {  
    console.error(`Failed to check approval for position #${tokenId}:`, error.message);  
  }  
}  
  
async function approvePosition(positionManager, lockerAddress, tokenId) {  
  if (!tokenId) {  
    console.error("Please provide a position ID");  
    return;  
  }  
      
  try {  
    console.log(`Approving locker contract (${lockerAddress}) to transfer position #${tokenId}...`);  
    const tx = await positionManager.approve(lockerAddress, tokenId);  
    console.log(`Transaction hash: ${tx.hash}`);  
    await tx.wait();  
    console.log(`✅ Approval successful!`);  
  } catch (error) {  
    console.error(`Failed to approve position #${tokenId}:`, error.message);  
  }  
}  
  
async function lockPosition(locker, tokenId) {  
  if (!tokenId) {  
    console.error("Please provide a position ID");  
    return;  
  }  
      
  try {  
    console.log(`Locking position #${tokenId}...`);  
    const tx = await locker.lockPosition(tokenId);  
    console.log(`Transaction hash: ${tx.hash}`);  
    const receipt = await tx.wait();  
        
    // Find the PositionLocked event  
    const event = receipt.events.find(e => e.event === 'PositionLocked');  
    if (event) {  
      const lockId = event.args.lockId.toString();  
      console.log(`✅ Position #${tokenId} locked successfully with lock ID: ${lockId}`);  
    } else {  
      console.log(`✅ Position locked but couldn't find lock ID in events`);  
    }  
  } catch (error) {  
    console.error(`Failed to lock position #${tokenId}:`, error.message);  
  }  
}  
  
async function collectFees(locker, lockId, recipient, amount0Max, amount1Max) {  
  if (!lockId) {  
    console.error("Please provide a lock ID");  
    return;  
  }  
      
  try {  
    console.log(`Collecting fees for lock ID #${lockId} to recipient ${recipient}...`);  
    const tx = await locker.collectFees(  
      lockId,  
      recipient,  
      amount0Max,  
      amount1Max  
    );  
    console.log(`Transaction hash: ${tx.hash}`);  
    const receipt = await tx.wait();  
        
    // Find the FeesCollected event  
    const event = receipt.events.find(e => e.event === 'FeesCollected');  
    if (event) {  
      const amount0 = event.args.amount0.toString();  
      const amount1 = event.args.amount1.toString();  
      console.log(`✅ Collected fees: ${amount0} of token0, ${amount1} of token1`);  
    } else {  
      console.log(`✅ Fees collected but couldn't find amounts in events`);  
    }  
  } catch (error) {  
    console.error(`Failed to collect fees for lock ID #${lockId}:`, error.message);  
  }  
}  
  
async function unlockPosition(locker, lockId) {  
  if (!lockId) {  
    console.error("Please provide a lock ID");  
    return;  
  }  
      
  try {  
    // Check if lock period has ended  
    const remainingLockTime = await locker.getRemainingLockTime();  
    if (remainingLockTime.gt(0)) {  
      console.error(`Lock period hasn't ended yet. Remaining time: ${remainingLockTime.toString()} seconds`);  
      return;  
    }  
        
    console.log(`Unlocking position for lock ID #${lockId}...`);  
    const tx = await locker.unlockPosition(lockId);  
    console.log(`Transaction hash: ${tx.hash}`);  
    await tx.wait();  
    console.log(`✅ Position unlocked successfully!`);  
  } catch (error) {  
    console.error(`Failed to unlock position for lock ID #${lockId}:`, error.message);  
  }  
}  
  
async function getPositionDetails(locker, tokenId) {  
  if (!tokenId) {  
    console.error("Please provide a position ID");  
    return;  
  }  
      
  try {  
    console.log(`Fetching details for position #${tokenId}...`);  
    const position = await locker.getPositionDetails(tokenId);  
        
    console.log(`\n=== Position #${tokenId} Details ===`);  
    console.log(`Token0: ${position.token0}`);  
    console.log(`Token1: ${position.token1}`);  
    console.log(`Fee Tier: ${position.fee}`);  
    console.log(`Tick Lower: ${position.tickLower}`);  
    console.log(`Tick Upper: ${position.tickUpper}`);  
    console.log(`Liquidity: ${position.liquidity.toString()}`);  
    console.log(`Tokens Owed0: ${position.tokensOwed0.toString()}`);  
    console.log(`Tokens Owed1: ${position.tokensOwed1.toString()}`);  
    console.log(`Fee Growth Inside0: ${position.feeGrowthInside0LastX128.toString()}`);  
    console.log(`Fee Growth Inside1: ${position.feeGrowthInside1LastX128.toString()}`);  
    console.log(`Nonce: ${position.nonce.toString()}`);  
    console.log(`Operator: ${position.operator}`);  
        
    // Check if this position is locked in the contract  
    const lockId = await locker.getLockIdForToken(tokenId);  
    if (lockId.gt(0)) {  
      console.log(`\nThis position is locked in the contract with Lock ID: ${lockId.toString()}`);  
          
      // Get locked position details  
      const lockedPosition = await locker.getLockedPosition(lockId);  
      console.log(`Owner: ${lockedPosition.owner}`);  
      console.log(`Locked At: ${new Date(lockedPosition.lockedAt.toNumber() * 1000).toISOString()}`);  
      console.log(`Is Withdrawn: ${lockedPosition.isWithdrawn}`);  
    } else {  
      console.log(`\nThis position is not currently locked in the contract.`);  
    }  
  } catch (error) {  
    console.error(`Failed to get details for position #${tokenId}:`, error.message);  
  }  
}  
  
main()  
  .then(() => process.exit(0))  
  .catch((error) => {  
    console.error(error);  
    process.exit(1);  
  });  
