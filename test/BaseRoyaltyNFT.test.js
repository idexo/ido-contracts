const { expect } = require("chai")
const { duration } = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants")
const RoyaltyNFT = artifacts.require("contracts/marketplace/direct/BaseRoyaltyNFT.sol:BaseRoyaltyNFT")

contract("::BaseRoyaltyNFT", async (accounts) => {
    let royaltyNFT
    const [owner, alice, bob, carol, darren] = accounts
    const DOMAIN = "https://idexo.com/"
    const startTime = Math.floor(Date.now() / 1000) + duration.days(1)

    before(async () => {
        royaltyNFT = await RoyaltyNFT.new("RoyaltyNFT", "RNFT", "", owner, 1, { from: owner })
    })

    describe("#Role", async () => {
        it("default operator", async () => {
            expect(await royaltyNFT.checkOperator(owner)).to.eq(true)
        })
        it("should add operator", async () => {
            await royaltyNFT.addOperator(bob, { from: owner })
            expect(await royaltyNFT.checkOperator(bob)).to.eq(true)
        })
        it("should check operator", async () => {
            await royaltyNFT.checkOperator(bob)
            expect(await royaltyNFT.checkOperator(bob)).to.eq(true)
        })
        it("should remove operator", async () => {
            await royaltyNFT.removeOperator(bob, { from: owner })
            expect(await royaltyNFT.checkOperator(bob)).to.eq(false)
        })
        it("supportsInterface", async () => {
            await royaltyNFT.supportsInterface(`0x00000000`).then((res) => {
                expect(res).to.eq(false)
            })
        })
        describe("reverts if", async () => {
            it("add operator by non-admin", async () => {
                await expectRevert(royaltyNFT.addOperator(bob, { from: bob }), "Ownable: caller is not the owner")
            })
            it("remove operator by non-admin", async () => {
                await royaltyNFT.addOperator(bob, { from: owner })
                await expectRevert(royaltyNFT.removeOperator(bob, { from: carol }), "Ownable: caller is not the owner")
            })
        })
    })

    describe("# baseTokenURI", async () => {
        it("should set baseTokenURI", async () => {
            await royaltyNFT.setBaseTokenURI(DOMAIN, { from: owner })
        })
    })

    describe("# RoyaltiesFeeBP", async () => {
        it("should set royaltiesFee", async () => {
            await royaltyNFT.setRoyaltiesFeeBP(1, { from: owner })
        })
        describe("should revert if", async () => {
            it("royalties > 10000", async () => {
                // This test is compromised until the size of the variable 'royaltiesFeeBP' is corrected in the contract
                // fixed to uint16
                await expectRevert(royaltyNFT.setRoyaltiesFeeBP(10001, { from: owner }), "INVALID_ROYALTIES_FEE")
            })
        })
    })

    describe("# RoyaltiesCollector", async () => {
        it("should set royaltiesCollector", async () => {
            await royaltyNFT.setRoyaltiesCollector(bob, { from: owner })
        })
        describe("should revert if", async () => {
            it("address Ox", async () => {
                await expectRevert(royaltyNFT.setRoyaltiesCollector(ZERO_ADDRESS, { from: owner }), "INVALID_ADDRESS")
            })
        })
    })

    describe("# Mint and Burn", async () => {
        it("should mint", async () => {
            expectEvent(await royaltyNFT.mint(alice, "alice", { from: owner }), "Minted")
        })
        it("should burn", async () => {
            expectEvent(await royaltyNFT.burn(1, { from: owner }), "Burned")
        })
    })

    describe("# TokenURI", async () => {
        it("should mint", async () => {
            expectEvent(await royaltyNFT.mint(alice, "alice", { from: owner }), "Minted")
        })
        it("should shows tokenURI", async () => {
            royaltyNFT.tokenURI(2, { from: owner }).then((tokenURI) => {
                expect(tokenURI).to.eq(DOMAIN + "alice")
            })
        })
        it("should return correct royalty amount", async() => {
            const tokenId = 2
            await royaltyNFT.setRoyaltiesFeeBP(1000, { from: owner })
            const salePrice = ethers.utils.parseEther("5"); // 5 ETH
            const expectedRoyaltyAmount = ethers.utils.parseEther("0.5");
            const result = await royaltyNFT.royaltyInfo(tokenId, salePrice);
            const royaltyAmount = result[1]
            expect(royaltyAmount.toString()).to.equal(expectedRoyaltyAmount.toString());

        })

        describe("should revert if", async () => {
            it("inexistent tokenId", async () => {
                await expectRevert(royaltyNFT.tokenURI(1, { from: owner }), "ERC721: invalid token ID")
            })
        })
    })
})
