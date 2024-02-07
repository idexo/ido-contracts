const { expect } = require("chai")
const { BN, constants, expectEvent } = require("@openzeppelin/test-helpers")
const { ethers } = require("hardhat")

describe("UncappedLinkedSoulboundFactory", function() {
	let UncappedLinkedSoulboundFactory, uncappedLinkedSoulboundFactory, UncappedLinkedSoulbound, accounts

	beforeEach(async function () {
		accounts = await ethers.getSigners()
		UncappedLinkedSoulbound = await ethers.getContractFactory("UncappedLinkedSoulbound")
		UncappedLinkedSoulboundFactory = await ethers.getContractFactory("UncappedLinkedSoulboundFactory")
		uncappedLinkedSoulboundFactory = await UncappedLinkedSoulboundFactory.deploy()
		await uncappedLinkedSoulboundFactory.deployed()
	})

	describe("createUncappedLinkedSoulbound", function () {
		it("should create a new instance of UncappedLinkedSoulbound", async function () {
			const collectionName = "Test Collection"
			const collectionSymbol = "TCT"
			const collectionBaseURI = ""

			const createTransaction = await uncappedLinkedSoulboundFactory.createUncappedLinkedSoulbound(
				collectionName,
				collectionSymbol,
				collectionBaseURI,
				accounts[0].address,
				accounts[0].address,
				{ from: accounts[0].address }
				)

			const createReceipt = await createTransaction.wait()

			expectEvent.inLogs(createReceipt.events, "UncappedLinkedSoulboundCreated", {
				creator: accounts[0].address
			})

			const newInstanceAddress = createReceipt.events.find((event) => event.event === "UncappedLinkedSoulboundCreated")
			.args.instance 

			const newInstance = UncappedLinkedSoulbound.attach(newInstanceAddress)

			await newInstance.connect(accounts[0]).acceptOwnership()

			expect(await newInstance.name()).to.equal(collectionName)
			expect(await newInstance.symbol()).to.equal(collectionSymbol)
			expect(await newInstance.baseURI()).to.equal(collectionBaseURI)
			expect(ethers.utils.getAddress(await newInstance.owner())).to.equal(ethers.utils.getAddress(accounts[0].address))
		})
	})
})

