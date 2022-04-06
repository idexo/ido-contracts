const { expect } = require("chai")
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const Payment = artifacts.require("contracts/payments/Payments.sol:Payments")
const ERC20 = artifacts.require("ERC20Mock")

contract("::Payments", async (accounts) => {
    let payment, cred
    const [owner, alice, bob, carol, darren] = accounts
    const BASE_URI = "https://idexo.io/"

    before(async () => {
        cred = await ERC20.new("CRED Coin", "CRED", { from: owner })
        usdc = await ERC20.new("USD Coin", "USDC", { from: owner })
        payment = await Payment.new("Idexo Receipt", "IRCPT", BASE_URI, cred.address, { from: owner })
    })

    describe("# Role", async () => {
        it("should add operator", async () => {
            await payment.addOperator(alice, { from: owner })
            expect(await payment.checkOperator(alice)).to.eq(true)
        })
        it("should remove operator", async () => {
            await payment.removeOperator(alice, { from: owner })
            expect(await payment.checkOperator(alice)).to.eq(false)
        })
        it("supportsInterface", async () => {
            await payment.supportsInterface("0x00").then((res) => {
                expect(res).to.eq(false)
            })
        })
        describe("reverts if", async () => {
            it("add operator by NO-OWNER", async () => {
                await expectRevert(payment.addOperator(bob, { from: alice }), "Ownable: CALLER_NO_OWNER")
            })
            it("remove operator by NO-OWNER", async () => {
                await payment.addOperator(bob, { from: owner })
                await expectRevert(payment.removeOperator(bob, { from: alice }), "Ownable: CALLER_NO_OWNER")
            })
        })
    })

    describe("# Payment Tokens", async () => {
        it("should add a new payment token", async () => {
            await payment.addPaymentToken(usdc.address, { from: owner })
            // expect(await payment.checkOperator(alice)).to.eq(true)
        })

        // describe("reverts if", async () => {
        //     it("add operator by NO-OWNER", async () => {
        //         await expectRevert(payment.addOperator(bob, { from: alice }), "Ownable: CALLER_NO_OWNER")
        //     })
        //     it("remove operator by NO-OWNER", async () => {
        //         await payment.addOperator(bob, { from: owner })
        //         await expectRevert(payment.removeOperator(bob, { from: alice }), "Ownable: CALLER_NO_OWNER")
        //     })
        // })
    })

    describe("# Products", async () => {
        it("should add operator", async () => {
            await payment.addOperator(bob, { from: owner })
            expect(await payment.checkOperator(bob)).to.eq(true)
        })
        it("should add a new product 1", async () => {
            await payment.addProduct("ID01", cred.address, web3.utils.toWei(new BN(1000)), true, { from: bob })
        })
        it("should add a new product 2", async () => {
            await payment.addProduct("ID02", cred.address, web3.utils.toWei(new BN(2000)), true, { from: bob })
        })

        it("should get products", async () => {
            let products = await payment.getProducts()
            console.log(products)

            let productOne = await payment.getProduct("ID01")
            console.log(productOne)
        })
        it("should returns empty product array", async () => {
            let products = await payment.getProducts()
            console.log(products)

            let product = await payment.getProduct("ID03")
            console.log(product)
        })

        // describe("reverts if", async () => {
        //     it("add reward token by NO-OPERATOR", async () => {
        //         await expectRevert(payment.addRewardToken(usdc.address, { from: alice }), "Operatorable: CALLER_NO_OPERATOR_ROLE")
        //     })
        // })
    })
    describe("# Payment Balance", async () => {
        before(async () => {
            for (const user of [alice, bob, carol, darren]) {
                await cred.mint(user, web3.utils.toWei(new BN(3000)))
                await cred.approve(payment.address, web3.utils.toWei(new BN(3000)), { from: user })
            }
        })
        it("should get payment balance", async () => {
            let balance = await cred.balanceOf(carol, { from: carol })
            // console.log("CRED balance:", balance.toString())
            // expect(await payment.checkOperator(bob)).to.eq(true)
        })
    })

    describe("# Purchase", async () => {
        // it("should get payment balance", async () => {
        //     let balance = await payment.checkPaymentBalance(cred.address, { from: carol })
        //     console.log("CRED balance:", balance.toString())
        //     // expect(await payment.checkOperator(bob)).to.eq(true)
        // })

        // it("should get product price", async () => {
        //     let productPrice = await payment.getPrice("ID01", { from: carol })
        //     console.log("Price:", productPrice.toString())
        //     // expect(await payment.checkOperator(bob)).to.eq(true)
        // })
        it("should purchase ID01", async () => {
            expect(await payment.hasPaid(carol)).to.eq(false)
            await payment.payProduct("ID01", { from: carol })
            expect(await payment.hasPaid(carol)).to.eq(true)
        })

        it("should purchase ID02", async () => {
            await payment.payProduct("ID02", { from: carol })
        })
        it("should show contract balance after purchase ID01", async () => {
            let contractBalance = await cred.balanceOf(payment.address, { from: owner })
            // console.log("Contract CRED Balance:", contractBalance.toString())
        })
        it("should show receipt balance after purchase ID01", async () => {
            let receiptBalance = await payment.balanceOf(carol, { from: carol })
            // console.log("Carol Receipts: ", receiptBalance.toString())
            let contractBalance = await cred.balanceOf(payment.address, { from: owner })
            // console.log("Contract CRED Balance:", contractBalance.toString())
        })

        it("should change openForSale attribute of product ID01", async () => {
            await payment.setOpenForSale("ID01", false, { from: owner })
        })

        it("should show receipts by account", async () => {
            let receipts = await payment.getReceiptIds(carol, { from: carol })
            console.log("Receipts: ", receipts.toString())
        })

        describe("reverts if", async () => {
            it("product not openForSale", async () => {
                await expectRevert(payment.payProduct("ID01", { from: alice }), "PRODUCT_UNAVAILABLE")
            })
        })
    })

    describe("# URI", async () => {
        it("should change tokenURI", async () => {
            await payment.setTokenURI(1, "test", { from: owner }),
                await payment.tokenURI(1).then((res) => {
                    expect(res.toString()).to.eq(BASE_URI + "test")
                })
        })
        it("should change baseURI", async () => {
            await payment.setBaseURI("http://newdomain/", { from: owner }),
                await payment.baseURI().then((res) => {
                    expect(res.toString()).to.eq("http://newdomain/")
                })
        })
        describe("reverts if", async () => {
            it("change tokenURI by NO-OPERATOR", async () => {
                await expectRevert(payment.setTokenURI(1, "test", { from: alice }), "Ownable: CALLER_NO_OWNER")
            })
        })
    })

    describe("# Refund", async () => {
        it("should show balance before refund ID01", async () => {
            let beforeBalance = await cred.balanceOf(carol, { from: carol })
            console.log("Carol Before Refund: ", beforeBalance.toString())
            let contractBalance = await cred.balanceOf(payment.address, { from: owner })
            console.log("Contract CRED before Balance:", contractBalance.toString())
        })
        it("should refund purchasedProduct from user", async () => {
            await payment.refund(carol, 1, { from: owner })
            let receiptBalance = await payment.balanceOf(carol, { from: carol })
            console.log("Carol Receipts: ", receiptBalance.toString())
        })
        it("should show balance after refund ID01", async () => {
            let afterBalance = await cred.balanceOf(carol, { from: carol })
            console.log("Carol after Refund: ", afterBalance.toString())
            let contractBalance = await cred.balanceOf(payment.address, { from: owner })
            console.log("Contract CRED after Balance:", contractBalance.toString())
        })
    })

    describe("# OpenForSale", async () => {
        it("should change openForSale attribute of product ID01", async () => {
            await payment.setOpenForSale("ID01", false, { from: owner })
            let product = await payment.getProduct("ID01", { from: carol })
            // console.log(product)
        })
    })

    describe("# PaidAmount", async () => {
        it("should show paid amount from a user", async () => {
            let paidAmount = await payment.getPaidAmount(carol, cred.address, { from: owner })
            console.log("Carol paid amount:", paidAmount.toString())
        })
    })

    describe("# Purchased", async () => {
        it("should show purchased products by account", async () => {
            let purchased = await payment.getPurchased(carol, { from: carol })
            // console.log(purchased)
        })
    })

    describe("# Receipts", async () => {
        it("should show receipts by account", async () => {
            let receipts = await payment.getReceiptIds(carol, { from: carol })
            // console.log("Receipts: ", receipts.toString())
        })

        it("should get receipt info", async () => {
            let receiptInfo = await payment.getReceiptInfo(2, { from: carol })
            // console.log("ReceiptInfo: ", receiptInfo)
        })
    })

    describe("# Current Supply", async () => {
        it("should show current receipts suply", async () => {
            let supply = await payment.currentSupply({ from: owner })
            console.log("Supply: ", supply.toString())
        })
    })

    describe("# Sweep", async () => {
        it("should sweep funds to another account", async () => {
            balance = await cred.balanceOf(payment.address)
            await payment.sweep(cred.address, darren, web3.utils.toWei(new BN(1000)), { from: owner })
        })
    })

    describe("# Transfer not allowed", async () => {
        it("should revert transfer", async () => {
            await expectRevert(payment.transferFrom(carol, alice, 2, { from: carol }), "NonTransferrableERC721Token: non transferrable")
        })
    })
})
