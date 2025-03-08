const { ethers, network } = require("hardhat");  
const fs = require("fs");  
const path = require("path");  
  
// Function to save deployment info  
const saveDeployment = (contractName, contract, networkName) => {  
  const deploymentDir = path.join(__dirname, "../deployments");  
  if (!fs.existsSync(deploymentDir)) {  
    fs.mkdirSync(deploymentDir, { recursive: true });  
  }  
    
  const deploymentPath = path.join(deploymentDir, `${networkName}.json`);  
  let deployments = {};  
      
  if (fs.existsSync(deploymentPath)) {  
    const existingDeployments = fs.readFileSync(deploymentPath, "utf8");  
    deployments = JSON.parse(existingDeployments);  
  }  
    
  deployments[contractName] = {  
    address: contract.address,  
    blockNumber: contract.deployTransaction ? contract.deployTransaction.blockNumber : "N/A",  
    deploymentHash: contract.deployTransaction ? contract.deployTransaction.hash : "N/A",  
    timestamp: new Date().toISOString(),  
  };  
    
  fs.writeFileSync(  
    deploymentPath,  
    JSON.stringify(deployments, null, 2)  
  );  
    
  console.log(`Deployment info saved to ${deploymentPath}`);  
};  
  
async function main() {  
  // Get network name  
  const networkName = network.name;  
  console.log(`Deploying Test IDO Token to ${networkName} network...`);  
    
  if (networkName !== 'sepolia' && !process.env.FORCE_DEPLOY) {  
    console.log(`This script is intended for Sepolia network. Current network: ${networkName}`);  
    console.log("If you want to deploy anyway, set FORCE_DEPLOY=true");  
    return;  
  }  
      
  // Get deployer account  
  const [deployer] = await ethers.getSigners();  
  console.log(`Deploying with account: ${deployer.address}`);  
      
  // Check deployer balance  
  const balance = await deployer.getBalance();  
  console.log(`Account balance: ${ethers.utils.formatEther(balance)} ETH`);  
    
  // Deploy IDO Token  
  console.log("Deploying IDO Token...");  
  const IDOToken = await ethers.getContractFactory("IDO");  
  const idoToken = await IDOToken.deploy();  
      
  await idoToken.deployed();  
  console.log(`IDO Token deployed to: ${idoToken.address}`);  
    
  // Save deployment info  
  saveDeployment("IDOToken", idoToken, networkName);  
    
  // Verify contract on Etherscan  
  if (networkName !== "hardhat" && networkName !== "localhost") {  
    console.log("Waiting for block confirmations before verification...");  
    // Wait for 5 block confirmations  
    await idoToken.deployTransaction.wait(5);  
        
    console.log("Verifying contract on Etherscan...");  
    try {  
      await hre.run("verify:verify", {  
        address: idoToken.address,  
        constructorArguments: [],  
      });  
      console.log("Contract verification completed!");  
    } catch (error) {  
      console.log("Verification failed:", error);  
    }  
  }  
    
  // Additional deployment steps - optional interactions  
  console.log("Performing additional setup for the token...");  
    
  // Example: Add another operator  
  if (process.env.OPERATOR_ADDRESS) {  
    console.log(`Adding ${process.env.OPERATOR_ADDRESS} as an operator...`);  
    const addOperatorTx = await idoToken.addOperator(process.env.OPERATOR_ADDRESS);  
    await addOperatorTx.wait();  
    console.log("Operator added successfully!");  
  }  
    
  // Log total supply  
  const totalSupply = await idoToken.totalSupply();  
  console.log(`Total supply: ${ethers.utils.formatEther(totalSupply)} IDO`);  
    
  console.log("Deployment completed successfully!");  
  console.log("----------------");  
  console.log("Summary:");  
  console.log(`- Network: ${networkName}`);  
  console.log(`- IDO Token: ${idoToken.address}`);  
  console.log(`- Deployer: ${deployer.address}`);  
  console.log(`- Total Supply: ${ethers.utils.formatEther(totalSupply)} IDO`);  
  console.log("----------------");  
  console.log("To use this token with your ProductPaymentContract, run:");  
  console.log(`PAYMENT_TOKEN=${idoToken.address} npx hardhat run scripts/deployProductPayment.js --network ${networkName}`);  
}  
  
main()  
  .then(() => process.exit(0))  
  .catch((error) => {  
    console.error(error);  
    process.exit(1);  
  });  
