const { expect } = require("chai");  
const { ethers, network } = require("hardhat");  
  
describe("ProductPaymentContract", function () {  
  let ProductPaymentContract;  
  let PaymentToken;  
  let contract;  
  let paymentToken;  
  let owner;  
  let user1;  
  let user2;  
      
  // Sample product data  
  const testProduct = {  
    name: "Product 1",  
    description: "Test product description",  
    metadataUrl: "https://test.com/metadata",  
    monthlyPrice: ethers.utils.parseEther("10"),  // 10 tokens  
    yearlyPrice: ethers.utils.parseEther("100"),  // 100 tokens  
    lifetimePrice: ethers.utils.parseEther("500"), // 500 tokens  
  };  
    
  // Define subscription periods  
  const PERIOD = {  
    MONTHLY: 0,  
    YEARLY: 1,  
    LIFETIME: 2  
  };  
    
  beforeEach(async function () {  
    // Get signers  
    [owner, user1, user2] = await ethers.getSigners();  
        
    // Deploy payment token  
    PaymentToken = await ethers.getContractFactory("ERC20Mock");  
    paymentToken = await PaymentToken.deploy("Payment Token", "PTK");  
    await paymentToken.deployed();  
        
    // Deploy the ProductPaymentContract  
    ProductPaymentContract = await ethers.getContractFactory("ProductPaymentContract");  
    contract = await ProductPaymentContract.deploy(paymentToken.address);  
    await contract.deployed();  
        
    // Mint tokens to test users  
    await paymentToken.mint(user1.address, ethers.utils.parseEther("1000"));  
    await paymentToken.mint(user2.address, ethers.utils.parseEther("1000"));  
        
    // Add a sample product  
    await contract.addProduct(  
      testProduct.name,  
      testProduct.description,  
      testProduct.metadataUrl,  
      testProduct.monthlyPrice,  
      testProduct.yearlyPrice,  
      testProduct.lifetimePrice  
    );  
  });  
    
  describe("Contract Initialization", function () {  
    it("Should set the right owner", async function () {  
      expect(await contract.owner()).to.equal(owner.address);  
    });  
    
    it("Should set the correct payment token", async function () {  
      expect(await contract.paymentToken()).to.equal(paymentToken.address);  
    });  
        
    it("Should initialize balances to zero", async function () {  
      expect(await contract.lockedBalance()).to.equal(0);  
      expect(await contract.withdrawableBalance()).to.equal(0);  
    });  
        
    it("Should have the correct NFT name and symbol", async function () {  
      expect(await contract.name()).to.equal("Product Receipt");  
      expect(await contract.symbol()).to.equal("RCPT");  
    });  
  });  
    
  describe("Product Management", function () {  
    it("Should correctly add a product", async function () {  
      const product = await contract.products(0);  
          
      expect(product.id).to.equal(0);  
      expect(product.name).to.equal(testProduct.name);  
      expect(product.description).to.equal(testProduct.description);  
      expect(product.metadataUrl).to.equal(testProduct.metadataUrl);  
      expect(product.monthlyPrice).to.equal(testProduct.monthlyPrice);  
      expect(product.yearlyPrice).to.equal(testProduct.yearlyPrice);  
      expect(product.lifetimePrice).to.equal(testProduct.lifetimePrice);  
      expect(product.active).to.equal(true);  
    });  
        
    it("Should emit ProductAdded event when product is added", async function () {  
      await expect(contract.addProduct(  
        "New Product",  
        "Description",  
        "https://example.com",  
        ethers.utils.parseEther("15"),  
        ethers.utils.parseEther("150"),  
        ethers.utils.parseEther("750")  
      ))  
        .to.emit(contract, "ProductAdded")  
        .withArgs(1, "New Product", "https://example.com");  
    });  
        
    it("Should revert when adding product with invalid prices", async function () {  
      await expect(contract.addProduct(  
        "Invalid Product",  
        "Description",  
        "https://example.com",  
        0, // Invalid price  
        ethers.utils.parseEther("150"),  
        ethers.utils.parseEther("750")  
      )).to.be.revertedWith("InvalidPrice");  
    });  
        
    it("Should correctly update a product", async function () {  
      await contract.updateProduct(  
        0,  
        "Updated Product",  
        "Updated description",  
        "https://updated.com",  
        ethers.utils.parseEther("20"),  
        ethers.utils.parseEther("200"),  
        ethers.utils.parseEther("1000")  
      );  
          
      const product = await contract.products(0);  
          
      expect(product.name).to.equal("Updated Product");  
      expect(product.description).to.equal("Updated description");  
      expect(product.metadataUrl).to.equal("https://updated.com");  
      expect(product.monthlyPrice).to.equal(ethers.utils.parseEther("20"));  
      expect(product.yearlyPrice).to.equal(ethers.utils.parseEther("200"));  
      expect(product.lifetimePrice).to.equal(ethers.utils.parseEther("1000"));  
    });  
        
    it("Should emit ProductUpdated event when product is updated", async function () {  
      await expect(contract.updateProduct(  
        0,  
        "Updated Product",  
        "Updated description",  
        "https://updated.com",  
        ethers.utils.parseEther("20"),  
        ethers.utils.parseEther("200"),  
        ethers.utils.parseEther("1000")  
      ))  
        .to.emit(contract, "ProductUpdated")  
        .withArgs(0, "Updated Product", "https://updated.com");  
    });  
        
    it("Should revert when updating non-existent product", async function () {  
      await expect(contract.updateProduct(  
        999, // Non-existent product ID  
        "Updated Product",  
        "Updated description",  
        "https://updated.com",  
        ethers.utils.parseEther("20"),  
        ethers.utils.parseEther("200"),  
        ethers.utils.parseEther("1000")  
      )).to.be.revertedWith("InvalidProduct");  
    });  
        
    it("Should correctly deactivate a product", async function () {  
      await contract.deactivateProduct(0);  
      const product = await contract.products(0);  
      expect(product.active).to.equal(false);  
    });  
        
    it("Should emit ProductDeactivated event when product is deactivated", async function () {  
      await expect(contract.deactivateProduct(0))  
        .to.emit(contract, "ProductDeactivated")  
        .withArgs(0);  
    });  
        
    it("Should correctly reactivate a product", async function () {  
      await contract.deactivateProduct(0);  
      await contract.reactivateProduct(0);  
      const product = await contract.products(0);  
      expect(product.active).to.equal(true);  
    });  
        
    it("Should emit ProductReactivated event when product is reactivated", async function () {  
      await contract.deactivateProduct(0);  
      await expect(contract.reactivateProduct(0))  
        .to.emit(contract, "ProductReactivated")  
        .withArgs(0);  
    });  
        
    it("Should revert when deactivating non-existent product", async function () {  
      await expect(contract.deactivateProduct(999))  
        .to.be.revertedWith("InvalidProduct");  
    });  
        
    it("Should correctly list active products", async function () {  
      // Add another product  
      await contract.addProduct(  
        "Product 2",  
        "Description 2",  
        "https://test2.com",  
        ethers.utils.parseEther("15"),  
        ethers.utils.parseEther("150"),  
        ethers.utils.parseEther("750")  
      );  
          
      // Deactivate first product  
      await contract.deactivateProduct(0);  
          
      const activeProducts = await contract.getActiveProducts();  
          
      expect(activeProducts.length).to.equal(1);  
      expect(activeProducts[0].id).to.equal(1);  
      expect(activeProducts[0].name).to.equal("Product 2");  
    });  
  });  
      
  describe("Payment Token Management", function () {  
    it("Should update the payment token correctly", async function () {  
      // Deploy a new token  
      const newToken = await PaymentToken.deploy("New Token", "NTK");  
      await newToken.deployed();  
          
      // Update payment token  
      await contract.updatePaymentToken(newToken.address);  
          
      expect(await contract.paymentToken()).to.equal(newToken.address);  
    });  
        
    it("Should emit PaymentTokenUpdated event when token is updated", async function () {  
      const newToken = await PaymentToken.deploy("New Token", "NTK");  
      await newToken.deployed();  
          
      await expect(contract.updatePaymentToken(newToken.address))  
        .to.emit(contract, "PaymentTokenUpdated")  
        .withArgs(paymentToken.address, newToken.address);  
    });  
        
    it("Should revert when updating to zero address", async function () {  
      await expect(contract.updatePaymentToken(ethers.constants.AddressZero))  
        .to.be.revertedWith("InvalidToken");  
    });  
  });  
      
  describe("Subscription Purchase", function () {  
    beforeEach(async function () {  
      // Approve token spending for users  
      await paymentToken.connect(user1).approve(contract.address, ethers.utils.parseEther("1000"));  
      await paymentToken.connect(user2).approve(contract.address, ethers.utils.parseEther("1000"));  
    });  
        
    it("Should purchase a monthly subscription successfully", async function () {  
      await contract.connect(user1).purchaseSubscription(0, PERIOD.MONTHLY);  
          
      const receipt = await contract.receipts(0);  
      expect(receipt.productId).to.equal(0);  
      expect(receipt.period).to.equal(PERIOD.MONTHLY);  
      expect(receipt.price).to.equal(testProduct.monthlyPrice);  
          
      // Check balances  
      expect(await contract.lockedBalance()).to.equal(testProduct.monthlyPrice.div(2));  
      expect(await contract.withdrawableBalance()).to.equal(testProduct.monthlyPrice.sub(testProduct.monthlyPrice.div(2)));  
          
      // Check NFT ownership  
      expect(await contract.ownerOf(0)).to.equal(user1.address);  
    });  
        
    it("Should purchase a yearly subscription successfully", async function () {  
      await contract.connect(user1).purchaseSubscription(0, PERIOD.YEARLY);  
          
      const receipt = await contract.receipts(0);  
      expect(receipt.productId).to.equal(0);  
      expect(receipt.period).to.equal(PERIOD.YEARLY);  
      expect(receipt.price).to.equal(testProduct.yearlyPrice);  
    });  
        
    it("Should purchase a lifetime subscription successfully", async function () {  
      await contract.connect(user1).purchaseSubscription(0, PERIOD.LIFETIME);  
          
      const receipt = await contract.receipts(0);  
      expect(receipt.productId).to.equal(0);  
      expect(receipt.period).to.equal(PERIOD.LIFETIME);  
      expect(receipt.price).to.equal(testProduct.lifetimePrice);  
          
      // Verify the expiry timestamp is maximum for lifetime  
      expect(receipt.expiryTimestamp).to.equal(ethers.constants.MaxUint256);  
    });  
        
    it("Should emit SubscriptionPurchased event on purchase", async function () {    
      // Track the transaction    
      const tx = await contract.connect(user1).purchaseSubscription(0, PERIOD.MONTHLY);    
      const receipt = await tx.wait();    
          
      // Find the SubscriptionPurchased event     
      const event = receipt.events.find(e => e.event === 'SubscriptionPurchased');    
          
      // Verify the event arguments    
      expect(event.args.buyer).to.equal(user1.address);    
      expect(event.args.productId).to.equal(0);    
      expect(event.args.receiptId).to.equal(0);    
      expect(event.args.period).to.equal(PERIOD.MONTHLY);    
      expect(event.args.price).to.equal(testProduct.monthlyPrice);    
          
      // For expiry timestamp, verify it's approximately 30 days in the future    
      const block = await ethers.provider.getBlock(receipt.blockNumber);    
      const expectedExpiry = block.timestamp + (30 * 24 * 60 * 60);    
          
      // Use a simpler approach for comparison    
      const expiryTimestamp = event.args.expiryTimestamp.toNumber();    
      const diff = Math.abs(expiryTimestamp - expectedExpiry);    
      expect(diff).to.be.lessThan(10); // Allow 10 seconds difference    
    });  
        
    it("Should revert purchase for non-existent product", async function () {  
      await expect(contract.connect(user1).purchaseSubscription(999, PERIOD.MONTHLY))  
        .to.be.revertedWith("InvalidProduct");  
    });  
        
    it("Should revert purchase for deactivated product", async function () {  
      await contract.deactivateProduct(0);  
          
      await expect(contract.connect(user1).purchaseSubscription(0, PERIOD.MONTHLY))  
        .to.be.revertedWith("ProductNotActive");  
    });  
        
    it("Should revert purchase with invalid period", async function () {  
      await expect(contract.connect(user1).purchaseSubscription(0, 9))  
        .to.be.revertedWith("InvalidPeriod");  
    });  
        
    it("Should revert purchase with insufficient allowance", async function () {  
      // Reset allowance to 0  
      await paymentToken.connect(user1).approve(contract.address, 0);  
          
      await expect(contract.connect(user1).purchaseSubscription(0, PERIOD.MONTHLY))  
        .to.be.revertedWith("InsufficientAllowance");  
    });  
  });  
      
  describe("Receipt Management and Queries", function () {  
    beforeEach(async function () {  
      // Approve token spending for users  
      await paymentToken.connect(user1).approve(contract.address, ethers.utils.parseEther("1000"));  
          
      // User1 purchases multiple subscriptions  
      await contract.connect(user1).purchaseSubscription(0, PERIOD.MONTHLY);  
          
      // Add another product  
      await contract.addProduct(  
        "Product 2",  
        "Description 2",  
        "https://test2.com",  
        ethers.utils.parseEther("15"),  
        ethers.utils.parseEther("150"),  
        ethers.utils.parseEther("750")  
      );  
          
      // Purchase for the second product  
      await contract.connect(user1).purchaseSubscription(1, PERIOD.YEARLY);  
    });  
        
    it("Should correctly get user receipts", async function () {  
      const userReceipts = await contract.getUserReceipts(user1.address);  
          
      expect(userReceipts.length).to.equal(2);  
      expect(userReceipts[0]).to.equal(0);  
      expect(userReceipts[1]).to.equal(1);  
    });  
        
    it("Should correctly check if receipt is valid", async function () {  
      // Both receipts should be valid initially  
      expect(await contract.isValidReceipt(0)).to.equal(true);  
      expect(await contract.isValidReceipt(1)).to.equal(true);  
          
      // Fast forward 31 days to make monthly pass expire  
      await network.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]);  
      await network.provider.send("evm_mine");  
          
      // Monthly receipt should now be invalid, but yearly is still valid  
      expect(await contract.isValidReceipt(0)).to.equal(false);  
      expect(await contract.isValidReceipt(1)).to.equal(true);  
    });  
        
    it("Should return false for non-existent receipt in isValidReceipt", async function () {  
      expect(await contract.isValidReceipt(999)).to.equal(false);  
    });  
        
    it("Should get correct receipt details", async function () {  
      const [  
        productId,  
        period,  
        price,  
        purchaseTimestamp,  
        expiryTimestamp,  
        productName,  
        isValid  
      ] = await contract.getReceiptDetails(0);  
          
      expect(productId).to.equal(0);  
      expect(period).to.equal(PERIOD.MONTHLY);  
      expect(price).to.equal(testProduct.monthlyPrice);  
      expect(productName).to.equal(testProduct.name);  
      expect(isValid).to.equal(true);  
    });  
        
    it("Should get correct tokenURI with embedded metadata", async function () {  
      const tokenURI = await contract.tokenURI(0);  
          
      expect(tokenURI).to.include('data:application/json;base64,');  
          
      // Decode Base64 and parse JSON  
      const encodedJson = tokenURI.replace('data:application/json;base64,', '');  
      const decodedJson = Buffer.from(encodedJson, 'base64').toString('utf-8');  
      const metadata = JSON.parse(decodedJson);  
          
      expect(metadata.name).to.include('Receipt #0');  
      expect(metadata.description).to.include(testProduct.name);  
          
      // Check attributes  
      const productIdAttr = metadata.attributes.find(a => a.trait_type === 'Product ID');  
      expect(productIdAttr.value).to.equal('0');  
          
      const productNameAttr = metadata.attributes.find(a => a.trait_type === 'Product Name');  
      expect(productNameAttr.value).to.equal(testProduct.name);  
          
      const subscriptionAttr = metadata.attributes.find(a => a.trait_type === 'Subscription');  
      expect(subscriptionAttr.value).to.equal('Monthly');  
    });  
        
    it("Should correctly use tokenOfOwnerByIndex to enumerate tokens", async function () {  
      const tokenId = await contract.tokenOfOwnerByIndex(user1.address, 0);  
      expect(tokenId).to.equal(0);  
          
      const secondTokenId = await contract.tokenOfOwnerByIndex(user1.address, 1);  
      expect(secondTokenId).to.equal(1);  
    });  
        
    it("Should revert when index is out of bounds in tokenOfOwnerByIndex", async function () {  
      await expect(contract.tokenOfOwnerByIndex(user1.address, 99))  
        .to.be.revertedWith("Index out of bounds");  
    });  
  });  
      
  describe("Balance and Withdrawals", function () {  
    beforeEach(async function () {  
      // Approve token spending for user  
      await paymentToken.connect(user1).approve(contract.address, ethers.utils.parseEther("1000"));  
          
      // User1 purchases subscription  
      await contract.connect(user1).purchaseSubscription(0, PERIOD.MONTHLY);  
    });  
        
    it("Should correctly track balances after purchase", async function () {  
      const halfPrice = testProduct.monthlyPrice.div(2);  
      const otherHalf = testProduct.monthlyPrice.sub(halfPrice);  
          
      expect(await contract.lockedBalance()).to.equal(halfPrice);  
      expect(await contract.withdrawableBalance()).to.equal(otherHalf);  
    });  
        
    it("Should allow owner to withdraw available balance", async function () {  
      const halfPrice = testProduct.monthlyPrice.div(2);  
      const otherHalf = testProduct.monthlyPrice.sub(halfPrice);  
          
      // Owner's initial balance  
      const initialBalance = await paymentToken.balanceOf(owner.address);  
          
      // Withdraw  
      await contract.withdraw(otherHalf);  
          
      // Check owner's new balance  
      const newBalance = await paymentToken.balanceOf(owner.address);  
      expect(newBalance).to.equal(initialBalance.add(otherHalf));  
          
      // Check contract's balances  
      expect(await contract.lockedBalance()).to.equal(halfPrice);  
      expect(await contract.withdrawableBalance()).to.equal(0);  
    });  
        
    it("Should emit WithdrawalMade event when withdrawing", async function () {  
      const halfPrice = testProduct.monthlyPrice.div(2);  
      const otherHalf = testProduct.monthlyPrice.sub(halfPrice);  
          
      await expect(contract.withdraw(otherHalf))  
        .to.emit(contract, "WithdrawalMade")  
        .withArgs(owner.address, otherHalf);  
    });  
        
    it("Should revert when trying to withdraw more than available", async function () {  
      const halfPrice = testProduct.monthlyPrice.div(2);  
      const otherHalf = testProduct.monthlyPrice.sub(halfPrice);  
          
      await expect(contract.withdraw(otherHalf.add(1)))  
        .to.be.revertedWith("NoWithdrawableBalance");  
    });  
        
    it("Should revert when trying to withdraw zero", async function () {  
      await expect(contract.withdraw(0))  
        .to.be.revertedWith("NoWithdrawableBalance");  
    });  
        
    it("Should revert when non-owner tries to withdraw", async function () {  
      const halfPrice = testProduct.monthlyPrice.div(2);  
      const otherHalf = testProduct.monthlyPrice.sub(halfPrice);  
          
      await expect(contract.connect(user1).withdraw(otherHalf))  
        .to.be.revertedWith("Ownable: caller is not the owner");  
    });  
  });  
      
  describe("Access Control", function () {  
    it("Should allow only owner to add products", async function () {  
      await expect(contract.connect(user1).addProduct(  
        "Product 2",  
        "Description 2",  
        "https://test2.com",  
        ethers.utils.parseEther("15"),  
        ethers.utils.parseEther("150"),  
        ethers.utils.parseEther("750")  
      )).to.be.revertedWith("Ownable: caller is not the owner");  
    });  
        
    it("Should allow only owner to update products", async function () {  
      await expect(contract.connect(user1).updateProduct(  
        0,  
        "Updated Product",  
        "Updated description",  
        "https://updated.com",  
        ethers.utils.parseEther("20"),  
        ethers.utils.parseEther("200"),  
        ethers.utils.parseEther("1000")  
      )).to.be.revertedWith("Ownable: caller is not the owner");  
    });  
        
    it("Should allow only owner to deactivate products", async function () {  
      await expect(contract.connect(user1).deactivateProduct(0))  
        .to.be.revertedWith("Ownable: caller is not the owner");  
    });  
        
    it("Should allow only owner to reactivate products", async function () {  
      await contract.deactivateProduct(0);  
          
      await expect(contract.connect(user1).reactivateProduct(0))  
        .to.be.revertedWith("Ownable: caller is not the owner");  
    });  
        
    it("Should allow only owner to update payment token", async function () {  
      const newToken = await PaymentToken.deploy("New Token", "NTK");  
      await newToken.deployed();  
          
      await expect(contract.connect(user1).updatePaymentToken(newToken.address))  
        .to.be.revertedWith("Ownable: caller is not the owner");  
    });  
  });  
}); 