const { expect } = require("chai")
const { ethers } = require("hardhat")
const utils = ethers.utils

const contractName = "SingleUsePayments"

describe(`::${contractName}`, () => {
    let payment, cred
    let deployer, alice, bob, carol, darren
    const BASE_URI = "https://idexo.io/"

    before(async () => {
        const Contract = await ethers.getContractFactory(contractName)
        const ERC20 = await ethers.getContractFactory("ERC20Mock")

        const signers = await ethers.getSigners()
        cred = await ERC20.deploy("CRED Coin", "CRED")
        usdc = await ERC20.deploy("USD Coin", "USDC")
        payment = await Contract.deploy("Idexo Receipt", "IRCPT", BASE_URI)
        ;[deployer, alice, bob, carol, darren] = signers
    })

    describe("# Role", async () => {
        it("should add operator", async () => {
            await payment.addOperator(alice.address)
            expect(await payment.checkOperator(alice.address)).to.eq(true)
        })
        it("should remove operator", async () => {
            await payment.removeOperator(alice.address)
            expect(await payment.checkOperator(alice.address)).to.eq(false)
        })

        describe("reverts if", async () => {
            it("add operator by NO-OWNER", async () => {
                await expect(payment.connect(alice).addOperator(bob.address)).to.be.revertedWith("Ownable: caller is not the owner")
            })
            it("remove operator by NO-OWNER", async () => {
                await payment.addOperator(bob.address)
                await expect(payment.connect(alice).removeOperator(bob.address)).to.be.revertedWith("Ownable: caller is not the owner")
            })
        })
    })

    describe("# Products", async () => {
        it("should add operator", async () => {
            await payment.addOperator(bob.address)
            expect(await payment.checkOperator(bob.address)).to.eq(true)
        })
        it("should add a new product 1", async () => {
            await payment.connect(bob).addProduct("ID01", cred.address, utils.parseEther("1000"), true)
        })
        it("should add a new product 2", async () => {
            await payment.connect(bob).addProduct("ID02", cred.address, utils.parseEther("2000"), true)
        })
        it("should add a new product 3", async () => {
            await payment.connect(bob).addProduct("ID03", usdc.address, utils.parseEther("5000"), true)
        })
        it("should get all productIds", async () => {
            let products = await payment.getProducts()
            expect(products.length).to.eq(3)
        })
        it("should returns a product ID02", async () => {
            let product = await payment.getProduct("ID02")
            expect(product.length).to.equal(1)
            expect(product[0].productId).to.equal("ID02")
        })

        describe("reverts if", async () => {
            it("invalid productId", async () => {
                await expect(payment.connect(alice).getProduct("ID04")).to.be.revertedWith("Payments#getProduct: INVALID_PRODUCT_ID")
            })
        })
    })

    describe("# Payment Balance", async () => {
        before(async () => {
            for (const user of [alice, bob, carol, darren]) {
                await cred.mint(user.address, utils.parseEther("5000"))
                await cred.connect(user).approve(payment.address, utils.parseEther("5000"))
                await usdc.mint(user.address, utils.parseEther("10000"))
                await usdc.connect(user).approve(payment.address, utils.parseEther("10000"))
            }
        })

        it("should show payment tokens balance", async () => {
            let balance = await cred.connect(carol).balanceOf(alice.address)
            expect(balance.toString()).to.eq(utils.parseEther("5000").toString())
            balance = await usdc.connect(carol).balanceOf(bob.address)
            expect(balance.toString()).to.eq(utils.parseEther("10000").toString())
        })
    })

    describe("# Purchase", async () => {
        it("should purchase ID01", async () => {
            let receiptBalance = await payment.balanceOf(carol.address)
            expect(receiptBalance.toString()).to.eq("0")
            await expect(payment.connect(carol).payProduct("ID01")).to.emit(payment, "Paid")
            receiptBalance = await payment.balanceOf(carol.address)
            expect(receiptBalance.toString()).to.eq("1")
        })

        it("should purchase ID02", async () => {
            let receiptBalance = await payment.balanceOf(carol.address)
            expect(receiptBalance.toString()).to.eq("1")
            await expect(payment.connect(carol).payProduct("ID02")).to.emit(payment, "Paid")
            receiptBalance = await payment.balanceOf(carol.address)
            expect(receiptBalance.toString()).to.eq("2")
        })

        it("should purchase ID03", async () => {
            let receiptBalance = await payment.balanceOf(bob.address)
            expect(receiptBalance.toString()).to.eq("0")
            await payment.connect(bob).payProduct("ID03")
            receiptBalance = await payment.balanceOf(bob.address)
            expect(receiptBalance.toString()).to.eq("1")
        })

        it("should show users balance after purchases", async () => {
            let userBalance = await cred.connect(carol).balanceOf(carol.address)
            expect(userBalance.toString()).to.eq(utils.parseEther("2000").toString())

            userBalance = await usdc.balanceOf(bob.address)
            expect(userBalance.toString()).to.eq(utils.parseEther("5000").toString())
        })
        it("should show payment balance after purchases", async () => {
            let contractBalance = await cred.balanceOf(payment.address)
            expect(contractBalance.toString()).to.eq(utils.parseEther("3000").toString())

            contractBalance = await usdc.balanceOf(payment.address)
            expect(contractBalance.toString()).to.eq(utils.parseEther("5000").toString())
        })
    })

    describe("# openForSale", async () => {
        it("should change openForSale attribute of product ID01", async () => {
            await payment.setOpenForSale("ID01", false)
        })

        describe("reverts if", async () => {
            it("product not openForSale", async () => {
                await expect(payment.connect(alice).payProduct("ID01")).to.revertedWith("Payments#payProduct: PRODUCT_UNAVAILABLE")
            })
        })
    })

    describe("# Current Supply", async () => {
        it("should show current receipts suply", async () => {
            let supply = await payment.currentSupply()
            expect(supply.toString()).to.eq("3")
        })
    })

    describe("# URI", async () => {
        it("should change tokenURI", async () => {
            await payment.setTokenURI(1, "test"),
                await payment.tokenURI(1).then((res) => {
                    expect(res.toString()).to.eq(BASE_URI + "test")
                })
        })
        it("should change baseURI", async () => {
            await payment.setBaseURI("http://newdomain/"),
                await payment.baseURI().then((res) => {
                    expect(res.toString()).to.eq("http://newdomain/")
                })
        })
        describe("reverts if", async () => {
            it("change tokenURI by NO-OPERATOR", async () => {
                await expect(payment.connect(alice).setTokenURI(2, "test")).to.revertedWith("Ownable: caller is not the owner")
            })
        })
    })

    describe("# Refund", async () => {
        it("should show balance before refund ID01", async () => {
            await cred
                .connect(carol)
                .balanceOf(carol.address)
                .then((res) => {
                    expect(res.toString()).to.eq(utils.parseEther("2000")).toString()
                })

            await cred.balanceOf(payment.address).then((res) => {
                expect(res.toString()).to.eq(utils.parseEther("3000")).toString()
            })
        })
        it("should refund purchasedProduct from user", async () => {
            await expect(payment.refund(1)).to.emit(payment, "Refund")

            await cred.balanceOf(carol.address).then((res) => {
                expect(res.toString()).to.eq(utils.parseEther("3000")).toString()
            })

            await cred.balanceOf(payment.address).then((res) => {
                expect(res.toString()).to.eq(utils.parseEther("2000")).toString()
            })

            await payment.balanceOf(carol.address).then((res) => {
                expect(res.toString()).to.eq("1")
            })
        })
    })

    describe("# Purchased", async () => {
        it("should show purchased products by carol", async () => {
            await payment
                .connect(carol)
                .getPurchased(carol.address)
                .then((res) => {
                    expect(res.length).to.eq(1)
                    expect(res[0].productId).to.eq("ID02")
                })
        })
        it("should show purchased products by bob", async () => {
            await payment
                .connect(bob)
                .getPurchased(bob.address)
                .then((res) => {
                    expect(res.length).to.eq(1)
                    expect(res[0].productId).to.eq("ID03")
                })
        })
        it("should returns if user purchased a especific product", async () => {
            await payment
                .connect(bob)
                .hasPurchased(bob.address, "ID03")
                .then((res) => {
                    expect(res).to.eq(true)
                })
        })
        it("should returns if user purchased a especifi product", async () => {
            await payment
                .connect(bob)
                .hasPurchased(bob.address, "ID01")
                .then((res) => {
                    expect(res).to.eq(false)
                })
        })

        describe("reverts if", async () => {
            it("productId not exists", async () => {
                await expect(payment.hasPurchased(carol.address, "ID05")).to.revertedWith("Payments#hasPurchased: INVALID_PRODUCT_ID")
            })
        })
    })

    describe("# Product Price", async () => {
        it("should update product price", async () => {
            await payment.setPrice("ID03", utils.parseEther("7000"))
        })

        describe("reverts if", async () => {
            it("sweep by NO-OPERATOR", async () => {
                await expect(payment.connect(darren).setPrice("ID03", utils.parseEther("500"))).to.revertedWith(
                    "Operatorable: CALLER_NO_OPERATOR_ROLE"
                )
            })
        })
    })

    describe("# Receipts", async () => {
        it("should show receipts by account", async () => {
            await payment.connect(carol).payProduct("ID03")
            await payment
                .connect(carol)
                .getReceiptIds(carol.address)
                .then((res) => {
                    expect(res.length).to.eq(2)
                    expect(res[0].toString()).to.eq("2")
                    expect(res[1].toString()).to.eq("4")
                })
        })

        it("should get receipt info", async () => {
            await payment
                .connect(carol)
                .getReceiptInfo(2)
                .then((res) => {
                    expect(res.productId).to.eq("ID02")
                    expect(res.paidAmount.toString()).to.eq(utils.parseEther("2000")).toString()
                    expect(res.hasUsed).to.eq(false)
                })

            await payment
                .connect(bob)
                .getReceiptInfo(3)
                .then((res) => {
                    expect(res.productId).to.eq("ID03")
                    expect(res.paidAmount.toString()).to.eq(utils.parseEther("5000")).toString()
                    expect(res.hasUsed).to.eq(false)
                })
        })
        describe("# Use Receipts", async () => {
            it("should mark a receipt as used", async () => {
                await payment.useReceipt(2, "useHash")
                await payment
                    .connect(carol)
                    .getReceiptInfo(2)
                    .then((res) => {
                        expect(res.productId).to.eq("ID02")
                        expect(res.paidAmount.toString()).to.eq(utils.parseEther("2000")).toString()
                        expect(res.hasUsed).to.eq(true)
                        expect(res.hashOfUse).to.eq("useHash")
                    })
            })
        })
    })

    describe("# Sweep", async () => {
        it("should sweep funds to another account", async () => {
            await cred.balanceOf(payment.address).then((res) => {
                expect(res.toString()).to.eq(utils.parseEther("2000")).toString()
            })

            await usdc.balanceOf(payment.address).then((res) => {
                expect(res.toString()).to.eq(utils.parseEther("12000")).toString()
            })

            await expect(payment.sweep(cred.address, darren.address, utils.parseEther("2000"))).to.emit(payment, "Swept")

            await expect(payment.sweep(usdc.address, darren.address, utils.parseEther("12000"))).to.emit(payment, "Swept")
        })
        describe("reverts if", async () => {
            it("sweep by NO-OPERATOR", async () => {
                await expect(payment.connect(carol).sweep(usdc.address, darren.address, utils.parseEther("12000"))).to.revertedWith(
                    "Operatorable: CALLER_NO_OPERATOR_ROLE"
                )
            })

            it("no funds for refund", async () => {
                await expect(payment.refund(3)).to.revertedWith("ERC20: transfer amount exceeds balance")
            })
        })
    })

    describe("# Transfer not allowed", async () => {
        it("should revert transfer", async () => {
            await expect(payment.connect(carol).transferFrom(carol.address, alice.address, 2)).to.revertedWith("ReceiptToken: NON_TRANSFERRABLE")
        })
    })
})
