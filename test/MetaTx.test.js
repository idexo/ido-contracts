const { expect } = require("chai")
const { ethers } = require("hardhat")

// helper function to make code more readable
async function deploy(name, ...params) {
  const Contract = await ethers.getContractFactory(name)
  return await Contract.deploy(...params).then(f => f.deployed())
}

// see https://eips.ethereum.org/EIPS/eip-712 for more info
const EIP712Domain = [
  { name: 'name', type: 'string' },
  { name: 'version', type: 'string' },
  { name: 'chainId', type: 'uint256' },
  { name: 'verifyingContract', type: 'address' }
]

const ForwardRequest = [
  { name: 'from', type: 'address' },
  { name: 'to', type: 'address' },
  { name: 'value', type: 'uint256' },
  { name: 'gas', type: 'uint256' },
  { name: 'nonce', type: 'uint256' },
  { name: 'data', type: 'bytes' },
]

function getMetaTxTypeData(chainId, verifyingContract) {
  return {
    types: {
      EIP712Domain,
      ForwardRequest,
    },
    domain: {
      name: 'MinimalForwarder',
      version: '0.0.1',
      chainId,
      verifyingContract,
    },
    primaryType: 'ForwardRequest',
  }
}

async function signTypedData(signer, from, data) {
  // Send the signTypedData RPC call
  const [method, argData] = ['eth_signTypedData_v4', JSON.stringify(data)]
  return await signer.send(method, [from, argData])
}

async function buildRequest(forwarder, input) {
  const nonce = await forwarder.getNonce(input.from).then(nonce => nonce.toString())
  return { value: 0, gas: 1e6, nonce, ...input }
}

async function buildTypedData(forwarder, request) {
  const chainId = await forwarder.provider.getNetwork().then(n => n.chainId)
  const typeData = getMetaTxTypeData(chainId, forwarder.address)
  return { ...typeData, message: request }
}

async function signMetaTxRequest(signer, forwarder, input) {
  const request = await buildRequest(forwarder, input)
  const toSign = await buildTypedData(forwarder, request)
  const signature = await signTypedData(signer, input.from, toSign)
  return { signature, request }
}

describe("BaseRoyaltyNFT", function() {
  beforeEach(async () => {
  // deploy the meta-tx forwarder contract
  this.forwarder = await deploy("MinimalForwarder")

  // deploy usdt contract
  this.usdt = await deploy("ERC20Mock", "USDT", "USDT")
  const usdt = this.usdt

  // get the accounts we are going to use
  this.accounts = await ethers.getSigners()
  const owner = this.accounts[0]
  const alice = this.accounts[1]
  const bob = this.accounts[2]
  
  // deploy the EIP-2771 compatible BaseRoyaltyNFT contract
  this.royaltyNFT = await deploy("BaseRoyaltyNFT", "Test Collection", "TCC", "",  owner.address, 1000, this.forwarder.address)

  // deploy the EIP-2771 compatible DirectSale contract
  this.directSale = await deploy("DirectSale", usdt.address, this.forwarder.address)
  
  
  })

  it("Transaction uses end user's funds for gas.", async () => {
  // extract the account to act as the end user and check its ETH balance
  const owner = this.accounts[0]
  const alice = this.accounts[1]
  const ownerFundsBefore = await ethers.provider.getBalance(owner.address)
  
  // connect operator's account to the RoyaltyNFT contract handle and mint an NFT to end user
  const royaltynft = this.royaltyNFT.connect(owner)
  await expect(royaltynft.mint(alice.address, "https://nftm3.com")).to.emit(royaltynft, 'Minted').withArgs(1, alice.address)
  
  // now check the end user's funds after the transaction has been sent
  const ownerFundsAfter = await ethers.provider.getBalance(owner.address)
  const ownerFundsWereUsed = (ownerFundsAfter < ownerFundsBefore)
  
  // End user's address was logged in the mint tx and their funds have been reduced
  expect(ownerFundsWereUsed).to.equal(true)
  })
  
  it("Transaction uses relayer's funds for gas.", async () => {
  // extract the account to act as the end user and check its ETH balance
  // as well as the account to act as relayer to pay gas
  const owner = this.accounts[0]
  const alice = this.accounts[1]
  const bob = this.accounts[2]
  
  const ownerFundsBefore = await ethers.provider.getBalance(owner.address)

  
  // connect the relayer account to the forwarder contract handle
  const minimalforwarder = this.forwarder.connect(alice)
  const royaltynft = this.royaltyNFT
  const directSale = this.directSale
  
  // construct the signed payload for the relayer to accept on the end user's behalf
  const { request, signature } = await signMetaTxRequest(owner.provider, minimalforwarder, {
    from: owner.address,
    to: royaltynft.address,
    data: royaltynft.interface.encodeFunctionData('mint', [bob.address, "https://nftm3.com"]),
  })
  
  // now pass the request and signature over to the relayer account and have the relayer account 
  // execute the meta-tx with it's own funds
  await expect(minimalforwarder.execute(request, signature)).to.emit(royaltynft, 'Minted').withArgs(1, bob.address)
  
  // check the end user's funds after the transaction has been sent, they should be untouched
  const ownerFundsAfter = await ethers.provider.getBalance(owner.address)
  const ownerFundsWereNotUsed = (ownerFundsAfter.toString() === ownerFundsBefore.toString())
  
  // End user's address was logged in the mint tx and their funds have not been used
  // User npx hardhat test --trace to see the event
  expect(ownerFundsWereNotUsed).to.equal(true)
  })

  it("User can list nft without paying gas.", async () => {
  // extract the account to act as the end user and check its ETH balance
  // as well as the relayer account
  const owner = this.accounts[0]
  const alice = this.accounts[1]
  const bob = this.accounts[2]
  
  const aliceFundsBefore = await ethers.provider.getBalance(alice.address)
  const bobFundsBefore = await ethers.provider.getBalance(bob.address)
  
  // connect the relayer account to the forwarder contract handle
  const minimalforwarder = this.forwarder.connect(owner)
  const royaltynft = this.royaltyNFT.connect(owner)
  const directSale = this.directSale
  
  // connect operator's account to the RoyaltyNFT contract handle and mint an NFT to end user
  await expect(royaltynft.mint(bob.address, "https://nftm3.com")).to.emit(royaltynft, 'Minted').withArgs(1, bob.address)

  //now let bob open a sale on the NFT without paying the gas

  // construct the signed payload for the relayer to accept on the bob's behalf
  const { request, signature } = await signMetaTxRequest(bob.provider, minimalforwarder, {
    from: bob.address,
    to: directSale.address,
    data: directSale.interface.encodeFunctionData('openForSale', [royaltynft.address, 1, 1000000]),
  })

  // now pass the request and signature over to the relayer account and have the relayer account 
  // execute the meta-tx with it's own funds
  await expect(minimalforwarder.execute(request, signature)).to.emit(directSale, 'SaleOpened').withArgs(1)
  
  // check the end user's funds after the transaction has been sent, they should be untouched
  const bobFundsAfter = await ethers.provider.getBalance(bob.address)
  const bobFundsWereNotUsed = (bobFundsAfter.toString() === bobFundsBefore.toString())
  
  // bob's address was logged in the open sale tx and their funds have not been used
  // User npx hardhat test --trace to see the event
  expect(bobFundsWereNotUsed).to.equal(true)
  })
})