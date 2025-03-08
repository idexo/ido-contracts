const { ethers, network } = require("hardhat");  
const fs = require("fs");  
const path = require("path");  
  
// Configuration for different networks  
const PAYMENT_TOKEN_ADDRESSES = {  
  mainnet: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // IDO on Ethereum Mainnet  
  sepolia: "0xbAad768eBD30eCCB620B5728889ce3c3d03728cA", // IDO on Sepolia 
};  
  
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
  console.log(`Deploying to ${networkName} network...`);  
  
  // Get payment token address for the current network  
  const paymentTokenAddress = process.env.PAYMENT_TOKEN ||   
                            PAYMENT_TOKEN_ADDRESSES[networkName] ||   
                            PAYMENT_TOKEN_ADDRESSES.hardhat;  
    
  console.log(`Using payment token address: ${paymentTokenAddress}`);  
    
  // Get deployer account  
  const [deployer] = await ethers.getSigners();  
  console.log(`Deploying with account: ${deployer.address}`);  
    
  // Check deployer balance  
  const balance = await deployer.getBalance();  
  console.log(`Account balance: ${ethers.utils.formatEther(balance)} ETH`);  
  
  // Deploy ProductPaymentContract  
  console.log("Deploying ProductPaymentContract...");  
  const ProductPaymentContract = await ethers.getContractFactory("ProductPaymentContract");  
  const productPaymentContract = await ProductPaymentContract.deploy(paymentTokenAddress);  
    
  await productPaymentContract.deployed();  
  console.log(`ProductPaymentContract deployed to: ${productPaymentContract.address}`);  
  
  // Save deployment info  
  saveDeployment("ProductPaymentContract", productPaymentContract, networkName);  
  
  // Verify contract on Etherscan (if not on local network)  
  if (networkName !== "hardhat" && networkName !== "localhost") {  
    console.log("Waiting for block confirmations before verification...");  
    // Wait for 5 block confirmations  
    await productPaymentContract.deployTransaction.wait(5);  
      
    console.log("Verifying contract on Etherscan...");  
    try {  
      await hre.run("verify:verify", {  
        address: productPaymentContract.address,  
        constructorArguments: [paymentTokenAddress],  
      });  
      console.log("Contract verification completed!");  
    } catch (error) {  
      console.log("Verification failed:", error);  
    }  
  }  
  
  console.log("Deployment completed successfully!");  
}  
  
main()  
  .then(() => process.exit(0))  
  .catch((error) => {  
    console.error(error);  
    process.exit(1);  
  }); 