const { expect } = require("chai")
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const Token = artifacts.require("contracts/token/Token.sol:Token")

contract("::Token", async (accounts) => {
    let token
    const [deployer, alice, bob, carol] = accounts

    before(async () => {
        token = await Token.new("My Testing Token", "MTT", 100000, { from: deployer })
    })

    describe("# Role", async () => {
        it("should add operator", async () => {
            await token.addOperator(alice, { from: deployer })
            expect(await token.checkOperator(alice)).to.eq(true)
        })
        it("should remove operator", async () => {
            await token.removeOperator(alice, { from: deployer })
            expect(await token.checkOperator(alice)).to.eq(false)
        })
        it("supportsInterface", async () => {
            await token.supportsInterface("0x00").then((res) => {
                expect(res).to.eq(false)
            })
        })
        describe("reverts if", async () => {
            it("add operator by owner", async () => {
                await expectRevert(token.addOperator(alice, { from: alice }), "Ownable: caller is not the owner")
            })
            it("remove operator by owner", async () => {
                await token.addOperator(alice, { from: deployer })
                await expectRevert(token.removeOperator(alice, { from: alice }), "Ownable: caller is not the owner")
            })
        })
    })

    describe("# Contract", async () => {
        describe("info", async () => {
            it("should get name, symbol and cap", async () => {
                let name, symbol, cap
                name = await token.name({ from: alice })
                symbol = await token.symbol({ from: alice })
                cap = await token.cap({ from: alice })
                expect(name).to.eq("My Testing Token")
                expect(symbol).to.eq("MTT")
                expect(cap.toString()).to.eq(web3.utils.toWei(new BN(100000)).toString())
            })
        })

        describe("mint", async () => {
            before(async () => {
                for (const user of [deployer, alice, bob, carol]) {
                    await token.mint(user, web3.utils.toWei(new BN(5000)), { from: deployer })
                }
            })
            it("check supply", async () => {
                await token.totalSupply({ from: deployer }).then((res) => {
                    expect(res.toString()).to.eq(web3.utils.toWei(new BN(20000)).toString())
                })
            })
            it("check balance", async () => {
                await token.balanceOf(alice, { from: alice }).then((res) => {
                    expect(res.toString()).to.eq(web3.utils.toWei(new BN(5000)).toString())
                })
            })
        })

        describe("transfer", async () => {
            it("should transfer", async () => {
                await token.transfer(bob, web3.utils.toWei(new BN(5000)), { from: alice }).then(async () => {
                    await token.balanceOf(alice, { from: alice }).then((res) => {
                        expect(res.toString()).to.eq(web3.utils.toWei(new BN(0)).toString())
                    })
                    await token.balanceOf(bob, { from: alice }).then((res) => {
                        expect(res.toString()).to.eq(web3.utils.toWei(new BN(10000)).toString())
                    })
                })
            })

            describe("reverts if", async () => {
                it("self transfer", async () => {
                    await expectRevert(token.transfer(alice, web3.utils.toWei(new BN(5000)), { from: alice }), "SELF_TRANSFER")
                })
            })
        })

        describe("max cap", async () => {
            it("mint max cap", async () => {
                await token.mint(deployer, web3.utils.toWei(new BN(80000)), { from: deployer })
                await token.totalSupply({ from: deployer }).then((res) => {
                    expect(res.toString()).to.eq(web3.utils.toWei(new BN(100000)).toString())
                })
            })

            describe("reverts if", async () => {
                it("max cap exceeded", async () => {
                    await expectRevert(token.mint(deployer, web3.utils.toWei(new BN(80000)), { from: deployer }), "ERC20Capped: cap exceeded")
                })
            })
        })
    })
})
