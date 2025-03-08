const { ethers } = require("hardhat");  
  
async function main() {  
  // Uniswap V3 Position Manager addresses  
  const positionManagerAddresses = {  
    mainnet: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88" 
  };  
  
  // Get the current network  
  const network = await ethers.provider.getNetwork();  
  const networkName = network.name === "homestead" ? "mainnet" : network.name;  
    
  // Get Position Manager address for the current network  
  const positionManagerAddress = positionManagerAddresses[networkName] || positionManagerAddresses.mainnet;  
    
  // Set lock duration (e.g. 1460 days in seconds)  
  const lockDuration = 1460 * 24 * 60 * 60;  
    
  console.log(`Deploying UniV3PositionLocker on ${networkName}...`);  
  console.log(`Using Position Manager: ${positionManagerAddress}`);  
  console.log(`Lock duration: ${lockDuration} seconds`);  
  
  // Deploy the contract  
  const UniV3PositionLocker = await ethers.getContractFactory("UniV3PositionLocker");  
  const locker = await UniV3PositionLocker.deploy(positionManagerAddress, lockDuration);  
  
  await locker.deployed();  
  
  console.log(`UniV3PositionLocker deployed to: ${locker.address}`);  
  console.log(`Lock end timestamp: ${await locker.lockEndTimestamp()}`);  
    
  // Wait for 30 seconds to make sure the contract is properly propagated  
  console.log("Waiting for 30 seconds before verification...");  
  await new Promise(resolve => setTimeout(resolve, 30000));  
    
  // Verify the contract on Etherscan  
  try {  
    await hre.run("verify:verify", {  
      address: locker.address,  
      constructorArguments: [positionManagerAddress, lockDuration],  
    });  
    console.log("Contract verified successfully");  
  } catch (error) {  
    console.error("Error verifying contract:", error);  
  }  
}  
  
main()  
  .then(() => process.exit(0))  
  .catch((error) => {  
    console.error(error);  
    process.exit(1);  
  });  