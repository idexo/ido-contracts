const { expect } = require("chai")
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const Payment = artifacts.require("contracts/payment/PaymentNew.sol:PaymentNew")
const ERC20 = artifacts.require("ERC20Mock")

contract("::PaymentMultipleRewards", async (accounts) => {
    let payment, cred
    const [owner, alice, bob, carol, darren] = accounts

    before(async () => {
        cred = await ERC20.new("CRED Coin", "CRED", { from: owner })
        payment = await Payment.new(cred.address, { from: owner })
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

    describe("# Products", async () => {
        it("should add operator", async () => {
            await payment.addOperator(bob, { from: owner })
            expect(await payment.checkOperator(bob)).to.eq(true)
        })
        it("should add a new product 1", async () => {
            await payment.addProduct("ID01", "Product one", cred.address, web3.utils.toWei(new BN(1000)), true, { from: bob })
        })
        it("should add a new product 2", async () => {
            await payment.addProduct("ID02", "Product two", cred.address, web3.utils.toWei(new BN(2000)), true, { from: bob })
        })

        it("should get products", async () => {
            let products = await payment.getProducts()
            console.log(products)

            let productOne = await payment.getProduct("ID03")
            console.log(productOne)
        })
        // it("should remove a product", async () => {
        //     await payment.remProduct("Product two", { from: bob })
        // })
        // it("should get products", async () => {
        //     let products = await payment.getProducts()
        //     console.log(products)

        //     // let productOne = await payment.getProduct("Product two")
        //     // console.log(productOne)
        // })
        // describe("reverts if", async () => {
        //     it("add reward token by NO-OPERATOR", async () => {
        //         await expectRevert(payment.addRewardToken(usdc.address, { from: alice }), "Operatorable: CALLER_NO_OPERATOR_ROLE")
        //     })
        // })
    })
    describe("# Payment Balance", async () => {
        before(async () => {
            for (const user of [alice, bob, carol, darren]) {
                await cred.mint(user, web3.utils.toWei(new BN(20000)))
                await cred.approve(payment.address, web3.utils.toWei(new BN(20000)), { from: user })
            }
        })
        it("should get payment balance", async () => {
            let balance = await payment.checkPaymentBalance(cred.address, { from: carol })
            console.log("CRED balance:", balance.toString())
            // expect(await payment.checkOperator(bob)).to.eq(true)
        })
    })

    describe("# Purchase", async () => {
        it("should get payment balance", async () => {
            let balance = await payment.checkPaymentBalance(cred.address, { from: carol })
            console.log("CRED balance:", balance.toString())
            // expect(await payment.checkOperator(bob)).to.eq(true)
        })

        it("should get product price", async () => {
            let productPrice = await payment.getPrice("ID01", { from: carol })
            console.log("Price:", productPrice.toString())
            // expect(await payment.checkOperator(bob)).to.eq(true)
        })
        it("should purchase ID01", async () => {
            await payment.purchaseProduct("ID01", { from: carol })
        })
        it("should show contract balance after purchase ID01", async () => {
            let contractBalance = await cred.balanceOf(payment.address, { from: owner })
            console.log("Contract CRED Balance:", contractBalance.toString())
        })
    })
})