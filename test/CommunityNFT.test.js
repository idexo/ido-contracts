const CommunityNFT = artifacts.require("CommunityNFT")

const { expect } = require("chai")
const { BN, constants, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")

contract("CommunityNFT", async (accounts) => {
    let nft
    const [alice, bob, carol, darren] = accounts

    before(async () => {
        nft = await CommunityNFT.new("TEST", "T", "", { from: carol })
    })

    describe("#Role", async () => {
        it("default operator", async () => {
            expect(await nft.checkOperator(carol)).to.eq(true)
        })
        it("should add operator", async () => {
            await nft.addOperator(bob, { from: carol })
            expect(await nft.checkOperator(bob)).to.eq(true)
        })
        it("should check operator", async () => {
            await nft.checkOperator(bob)
            expect(await nft.checkOperator(bob)).to.eq(true)
        })
        it("should remove operator", async () => {
            await nft.removeOperator(bob, { from: carol })
            expect(await nft.checkOperator(bob)).to.eq(false)
        })
        it("supportsInterface", async () => {
            await nft.supportsInterface(`0x00000000`).then((res) => {
                expect(res).to.eq(false)
            })
        })
        describe("reverts if", async () => {
            it("add operator by non-admin", async () => {
                await expectRevert(nft.addOperator(bob, { from: bob }), "Ownable: caller is not the owner")
            })
            it("remove operator by non-admin", async () => {
                await nft.addOperator(bob, { from: carol })
                await expectRevert(nft.removeOperator(bob, { from: bob }), "Ownable: caller is not the owner")
            })
        })
    })

    describe("#Mint", async () => {
        it("should mint NFT", async () => {
            expectEvent(await nft.mintNFT(alice, "https://idexo.com/111", { from: bob }), "NFTCreated")
            const balance = await nft.balanceOf(alice)
            expect(balance.toString()).to.eq("1")
            const tokenId = await nft.getTokenId(alice)
            expect(tokenId.toString()).to.eq("1")
        })
        describe("reverts if", async () => {
            it("caller no operator role", async () => {
                await expectRevert(nft.mintNFT(alice, "https://idexo.com/122", { from: alice }), "CALLER_NO_OPERATOR_ROLE")
            })
            it("account already has nft", async () => {
                await expectRevert(nft.mintNFT(alice, "https://idexo.com/133", { from: bob }), "ACCOUNT_ALREADY_HAS_NFT")
            })
            it("mint to the zero address", async () => {
                expect((await nft.tokenIds()).toString()).to.eq("1")
                await expectRevert(nft.mintNFT(constants.ZERO_ADDRESS, "144", { from: bob }), "ERC721: address zero is not a valid owner")
                expect((await nft.tokenIds()).toString()).to.eq("1")
            })
        })
    })

    describe("#Transfer", async () => {
        it("should transfer NFT", async () => {
            await nft.mintNFT(carol, "222", { from: bob })
            const ids = await nft.tokenIds()
            expect(ids.toString()).to.eq("2")
            const balance = await nft.balanceOf(carol)
            expect(balance.toString()).to.eq("1")
            let tokenId = await nft.getTokenId(carol)
            expect(tokenId.toString()).to.eq("2")
            await nft.setApprovalForAll(bob, true, { from: carol })
            expectEvent(await nft.transferFrom(carol, darren, 2, { from: bob }), "Transfer")
            tokenId = await nft.getTokenId(carol)
            expect(tokenId.toString()).to.eq("0")
            tokenId = await nft.getTokenId(darren)
            expect(tokenId.toString()).to.eq("2")
        })
        it("should transfer first NFT", async () => {
            let tokenId = await nft.getTokenId(alice)
            expect(tokenId.toString()).to.eq("1")
            await nft.setApprovalForAll(bob, true, { from: alice })
            expectEvent(await nft.transferFrom(alice, carol, 1, { from: bob }), "Transfer")
            tokenId = await nft.getTokenId(alice)
            expect(tokenId.toString()).to.eq("0")
            tokenId = await nft.getTokenId(carol)
            expect(tokenId.toString()).to.eq("1")
        })
        describe("reverts if", async () => {
            it("account to = 0x", async () => {
                await nft.setApprovalForAll(bob, true, { from: darren })
                await expectRevert(nft.transferFrom(darren, constants.ZERO_ADDRESS, 2, { from: bob }), "TRANSFER_TO_THE_ZERO_ADDRESS")
            })
            it("account already has nft", async () => {
                await nft.setApprovalForAll(bob, true, { from: darren })
                await expectRevert(nft.transferFrom(darren, carol, 2, { from: bob }), "ACCOUNT_ALREADY_HAS_NFT")
            })
        })
    })

    describe("#MoveNFT", async () => {
        it("should transfer NFT without approve", async () => {
            //add darren operator role
            await nft.addOperator(darren, { from: carol })
            expectEvent(await nft.moveNFT(carol, alice, 1, { from: darren }), "Transfer")
            let balance = await nft.balanceOf(carol)
            expect(balance.toString()).to.eq("0")
            balance = await nft.balanceOf(alice)
            expect(balance.toString()).to.eq("1")
        })
        describe("reverts if", async () => {
            it("caller no operator role", async () => {
                await expectRevert(nft.moveNFT(carol, alice, 1, { from: alice }), "CALLER_NO_OPERATOR_ROLE")
            })
        })
    })

    describe("#URI", async () => {
        it("should set token URI", async () => {
            expect(await nft.tokenURI(1)).to.eq("https://idexo.com/111")
            await nft.setTokenURI(1, "https://idexo.com/NewTokenURI", { from: bob })
            expect(await nft.tokenURI(1)).to.eq("https://idexo.com/NewTokenURI")
        })
        it("should set base token URI", async () => {
            // Just for testing, we will not use baseURI
            await nft.setBaseURI("https://newBaseURI.com/", { from: carol })
            expect(await nft.baseURI()).to.eq("https://newBaseURI.com/")
        })
        describe("reverts if", async () => {
            it("caller no owner", async () => {
                await expectRevert(nft.setBaseURI("https://idexo.com/", { from: bob }), "Ownable: caller is not the owner")
            })
        })
    })
    describe("#Earned CRED", async () => {
        it("should update CRED earned", async () => {
            expectEvent(
                await nft.updateNFTCredEarned(1, web3.utils.toWei(new BN(20000)), {
                    from: bob
                }),
                "CREDAdded"
            )
            const checkCred = await nft.credEarned(1)
            expect(web3.utils.fromWei(checkCred.toString(), "ether")).to.eq("20000")
        })
        describe("reverts if", async () => {
            it("caller no operator role", async () => {
                await expectRevert(
                    nft.updateNFTCredEarned(1, web3.utils.toWei(new BN(20000)), {
                        from: alice
                    }),
                    "CALLER_NO_OPERATOR_ROLE"
                )
            })
        })
    })
    describe("#Community Rank", async () => {
        it("should update NFT rank", async () => {
            expectEvent(
                await nft.updateNFTRank(1, "Early Idexonaut", {
                    from: bob
                }),
                "RankUpdated"
            )
            const checkRank = await nft.communityRank(1)
            expect(checkRank).to.eq("Early Idexonaut")
        })
        describe("reverts if", async () => {
            it("caller no operator role", async () => {
                await expectRevert(
                    nft.updateNFTRank(1, "Early Idexonaut", {
                        from: alice
                    }),
                    "CALLER_NO_OPERATOR_ROLE"
                )
            })
        })
    })
})
