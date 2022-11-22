const { expect } = require("chai")
const { ethers } = require("hardhat")

const contractName = "UncappedLinkedSoulbound"

describe(`::Contract -> ${contractName}`, () => {
	const name = "SBT Linked"
	const symbol = "SBTL"
	const baseURI = ""
	const linkedChainId = 5
	const linkedContractAddress = "0x7428c044400a8c54c5685a7b186bf80a65b9b6da"
	const linkedTokenId = 1

	let contract
	let deployer, alice, bob, carol, darren
	before(async () => {
		const Contract = await ethers.getContractFactory(contractName)
		const signers = await ethers.getSigners()

        contract = await Contract.deploy(name, symbol, baseURI)
        ;[deployer, alice, bob, carol, darren] = signers

	})
	describe("# Get Contract info", async () => {
        it("should get name", async () => {
            await contract.name().then((res) => {
                expect(res.toString()).to.eq(name)
            })
        })
        it("supportsInterface", async () => {
            await contract.supportsInterface(`0x00000000`).then((res) => {
                expect(res).to.eq(false)
            })
        })
        it("getCollectionIds", async () => {
            await contract.getCollectionIds(alice.address).then((res) => {
                expect(res.length).to.eq(0)
            })
        })
    })

    describe("# Mint for accounts", async () => {
        it("mint Soulbound NFTs", async () => {
            const defaultTokenURI = "https://idexo.com"
            await contract.mintSBT(alice.address, defaultTokenURI)
            await contract.mintSBT(bob.address, defaultTokenURI)
            await contract.mintSBT(carol.address, defaultTokenURI)
            await contract.mintSBT(alice.address, defaultTokenURI)

            expect(await contract.balanceOf(alice.address)).to.equal(2)

            expect(await contract.isHolder(bob.address)).to.equal(true)
        })
        it("mint batch Soulbound NFTs", async () => {
            await contract.mintBatchSBT([darren.address, darren.address], ["", ""])
            expect(await contract.balanceOf(darren.address)).to.equal(2)
        })
    })

    describe("# Locked transfers", async () => {
        it("try transfer", async () => {
            await contract.transferFrom(bob.address, alice.address, 2)
            await contract.safeTransferFrom(alice.address, bob.address, 2)
            await contract.transferFrom(bob.address, alice.address, 2)
            await contract.balanceOf(alice.address).then((res) => { expect(res).to.equal(3) })
        })

        describe("## Revert if", async () => {
            it("not owner", async () => {
                await expect(contract.connect(carol).transferFrom(carol.address, alice.address, 3)).to.revertedWith(
                    "TRANSFER_LOCKED_ON_SBT"
                )
            })
        })
    })

    describe("# Add LinkedNFT to SBT", async () => {
    	it("add linked NFT", async() => {
    		const defaultTokenURI = "https://idexo.com"
            await contract.mintSBT(alice.address, defaultTokenURI)
    		await contract.addLinkedNFT(1, linkedChainId, linkedContractAddress, linkedTokenId)
    		console.log(contract.getLinkedNFTs(1).then(res => console.log(res)))

    		expect(await contract.getLinkedNFTs(1)).to.have.lengthOf(1)
    	})
    })
})