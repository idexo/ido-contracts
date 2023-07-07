const { expect } = require("chai")
const { duration } = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const DirectSaleNFTs = artifacts.require("contracts/marketplace/direct/DirectSaleNFTs.sol:DirectSaleNFTs")
const ERC20 = artifacts.require("ERC20Mock")
const Forwarder = artifacts.require("Forwarder")
const CommunityNFT = artifacts.require("CommunityNFT")

contract("::DirectSaleNFTs", async (accounts) => {
    let directSale, nft, ido, usdt, usdc
    const [owner, alice, bob, carol, darren] = accounts
    const DOMAIN = "https://idexo.com/"

    before(async () => {
        const startTime = Math.floor(Date.now() / 1000) + duration.seconds(3600)
        ido = await ERC20.new("Idexo Community", "IDO", { from: owner })
        forwarder = await Forwarder.new({ from: owner })
        nft = await CommunityNFT.new("TEST", "T", DOMAIN, { from: owner })
        directSale = await DirectSaleNFTs.new(ido.address, forwarder.address, { from: owner })
    })

    // describe("# SaleStartTime", async () => {
    //     it("should set sale start time", async () => {
    //         await directSale.setSaleStartTime(Math.floor(Date.now() / 1000) + duration.seconds(2400), { from: owner })
    //     })
    //     describe("should revert if", async () => {
    //         it("timestamp < block.timestamp", async () => {
    //             await expectRevert(
    //                 directSale.setSaleStartTime(Math.floor(Date.now() / 1000) - duration.seconds(2400), { from: owner }),
    //                 "INVALID_SALE_START"
    //             )
    //         })
    //         it("sale started", async () => {
    //             await timeTraveler.advanceTimeAndBlock(duration.days(1))
    //             await expectRevert(
    //                 directSale.setSaleStartTime(Math.floor(Date.now() / 1000) + duration.seconds(2400), { from: owner }),
    //                 "SALE_STARTED"
    //             )
    //             // await timeTraveler.advanceTimeAndBlock(duration.days(-1))
    //         })
    //     })
    // })

    describe("# Open For Sale", async () => {
        it("should put alice NFT for sale", async () => {
            await nft.mintNFT(alice, `alice`, { from: owner })
            await nft.balanceOf(alice, { from: owner }).then((balance) => {
                expect(balance.toString()).to.eq("1")
            })
            expectEvent(await directSale.openForSale(nft.address, 1, web3.utils.toWei(new BN(10000)).toString(), { from: alice }), "SaleOpened")
            await nft.approve(directSale.address, 1, { from: alice })
        })
        it("should put bob NFT for sale", async () => {
            await nft.mintNFT(bob, `bob`, { from: owner })
            await nft.balanceOf(bob, { from: owner }).then((balance) => {
                expect(balance.toString()).to.eq("1")
            })
            expectEvent(await directSale.openForSale(nft.address, 2, web3.utils.toWei(new BN(10000)).toString(), { from: bob }), "SaleOpened")
            await nft.approve(directSale.address, 2, { from: bob })
        })
        it("should put darren NFT for sale", async () => {
            await nft.mintNFT(darren, `darren`, { from: owner })
            await nft.balanceOf(darren, { from: owner }).then((balance) => {
                expect(balance.toString()).to.eq("1")
            })
            expectEvent(await directSale.openForSale(nft.address, 3, web3.utils.toWei(new BN(10000)).toString(), { from: darren }), "SaleOpened")
            await nft.approve(directSale.address, 3, { from: darren })
        })

        describe("should revert if", async () => {
            it("token nonexistent", async () => {
                await expectRevert(
                    directSale.openForSale(nft.address, 4, web3.utils.toWei(new BN(10000)).toString(), { from: carol }),
                    "ERC721: invalid token ID"
                )
            })
            it("not owner", async () => {
                await expectRevert(
                    directSale.openForSale(nft.address, 1, web3.utils.toWei(new BN(10000)).toString(), { from: carol }),
                    "CALLER_NOT_NFT_OWNER"
                )
            })
        })
    })

    describe("# Price", async () => {
        it("should set new Price", async () => {
            expectEvent(await directSale.setPrice(1, nft.address, 1, web3.utils.toWei(new BN(20000)).toString(), { from: alice }), "PriceSet")
        })

        describe("should revert if", async () => {
            it("price 0", async () => {
                await expectRevert(directSale.setPrice(1, nft.address, 1, 0, { from: alice }), "INVALID_PRICE")
            })
        })
    })

    describe("# Close For Sale", async () => {
        it("should close to sale", async () => {
            expectEvent(await directSale.closeForSale(2, nft.address, 2, { from: bob }), "SaleClosed")
        })

        describe("should revert if", async () => {
            it("not owner or ownership changed", async () => {
                await expectRevert(
                    directSale.closeForSale(3, nft.address, 3, { from: alice }),
                    "CALLER_NOT_NFT_OWNER_OR_TOKEN_INVALID"
                )
            })
        })
    })

    describe("# Purchase", async () => {
        it("should bought the NFT #1", async () => {
            await ido.mint(carol, web3.utils.toWei(new BN(50000)).toString(), { from: owner })
            await ido.approve(directSale.address, web3.utils.toWei(new BN(500000)).toString(), { from: carol })

            expectEvent(await directSale.purchase(nft.address, 1, { from: carol }), "Purchased")
        })

        describe("should revert if", async () => {
            it("#sale closed", async () => {
                await expectRevert(directSale.purchase(nft.address, 2, { from: alice }), "NFT_SALE_CLOSED")
            })
            it("sef purchase", async () => {
                await expectRevert(directSale.purchase(nft.address, 3, { from: darren }), "SELF_PURCHASE")
            })
            it("#ownership changed", async () => {
                expect((await directSale.nftSales(nft.address, 3)).isOpenForSale).to.eq(true)
                await nft.transferFrom(darren, alice, 3, { from: darren })
                expectEvent.notEmitted(await directSale.purchase(nft.address, 3, { from: darren }), "Purchased")
                expect((await directSale.nftSales(nft.address, 3)).isOpenForSale).to.eq(false)
                await expectRevert(directSale.purchase(nft.address, 3, { from: darren }), "NFT_SALE_CLOSED")
            })
        })
    })

    describe("# Sweep", async () => {
        it("should sweept balance to another wallet", async () => {
            await directSale.sweep(ido.address, alice, { from: owner })
        })

        describe("should revert if", async () => {
            it("not owner", async () => {
                await expectRevert(directSale.sweep(ido.address, alice, { from: bob }), "Ownable: caller is not the owner")
            })
        })
    })
})
