// Initiate `ownerPrivateKey` with the third account private key on test evm

const { expect } = require("chai")
const { ethers, waffle } = require("hardhat")
const { BN, constants, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const { PERMIT_TYPEHASH, getPermitDigest, getDomainSeparator, sign } = require("./helpers/signature")

const RelayManager2 = artifacts.require("RelayManager2")
const ERC20PermitMock = artifacts.require("ERC20PermitMock")

contract("RelayManager2", async (accounts) => {
    let relayManager
    let ido
    const [alice, bob, carol] = accounts
    const idoName = "Idexo Token"
    const idoSymbol = "IDO"
    const ownerPrivateKey = Buffer.from("08c83289b1b8cce629a1e58b65c25b1c8062d5c9ec6375dc8265ad13ba25c630", "hex")

    before(async () => {
        ido = await ERC20PermitMock.new(idoName, idoSymbol)
        relayManager = await RelayManager2.new(ido.address, new BN(30))

        ido.mint(alice, web3.utils.toWei(new BN(1000)))
        ido.mint(carol, web3.utils.toWei(new BN(1000)))
        ido.mint(relayManager.address, web3.utils.toWei(new BN(1000)))
        await ido.approve(relayManager.address, web3.utils.toWei(new BN(1000)), { from: alice })
    })

    describe("#Role", async () => {
        it("should add operator", async () => {
            await relayManager.addOperator(bob)
            expect(await relayManager.checkOperator(bob)).to.eq(true)
        })
        it("should remove operator", async () => {
            await relayManager.removeOperator(bob)
            expect(await relayManager.checkOperator(bob)).to.eq(false)
        })
        describe("reverts if", async () => {
            it("add operator by non-admin", async () => {
                await expectRevert(relayManager.addOperator(bob, { from: bob }), "RelayManager2: CALLER_NO_OWNER")
            })
            it("remove operator by non-admin", async () => {
                await relayManager.addOperator(bob)
                await expectRevert(relayManager.removeOperator(bob, { from: bob }), "RelayManager2: CALLER_NO_OWNER")
            })
        })
    })

    describe("#Fund contract", async () => {
        it("should fund contract and emit event", async () => {
            const value = web3.utils.toWei(new BN(1), "ether")
            expectEvent(await relayManager.sendTransaction({value : value, from: alice}), "EthReceived")
            // instance provider
            const provider = waffle.provider
            const balance = await provider.getBalance(relayManager.address)
            expect(balance.toString()).to.eq(value.toString())
        })
    })

    describe("cross-chain transfer", async () => {
        let adminFee, gasFee, receiveAmount
        const sendAmount = web3.utils.toWei(new BN(100))
        const dummyDepositHash = "0xf408509b00caba5d37325ab33a92f6185c9b5f007a965dfbeff7b81ab1ec871b"
        const polygonChainId = new BN(137)

        it("deposit", async () => {
            // Start transfer to Polygon (alice => bob)
            expectEvent(await relayManager.deposit(bob, sendAmount, polygonChainId, { from: alice }), "Deposited")
        })
        it("send", async () => {
            expectEvent(await relayManager.send(bob, sendAmount, dummyDepositHash, 1, { from: bob }), "Sent")
            adminFee = await relayManager.adminFeeAccumulated()
            expect(adminFee.toString()).to.eq("300000000000000000")
            gasFee = await relayManager.gasFeeAccumulated()
            receiveAmount = sendAmount.sub(adminFee).sub(gasFee)
            await ido.balanceOf(bob).then((res) => {
                expect(res.toString()).to.eq(receiveAmount.toString())
            })
        })
        it("withdrawAdminFee", async () => {
            expectEvent(await relayManager.withdrawAdminFee(alice, adminFee), "AdminFeeWithdraw")
            await relayManager.adminFeeAccumulated().then((res) => {
                expect(res.toString()).to.eq("0")
            })
        })
        it("withdrawGasFee", async () => {
            expectEvent(await relayManager.withdrawGasFee(alice, gasFee), "GasFeeWithdraw")
            await relayManager.gasFeeAccumulated().then((res) => {
                expect(res.toString()).to.eq("0")
            })
        })
    })

    describe("#Ownership", async () => {
        it("should transfer ownership", async () => {
            await relayManager.transferOwnership(bob)
            await relayManager.acceptOwnership({ from: bob })
            expect(await relayManager.owner()).to.eq(bob)
        })
        it("setAdminFee", async () => {
            expectEvent(await relayManager.setAdminFee(1, { from: bob }), "AdminFeeChanged")
        })
        it("setBaseGas", async () => {
            await relayManager.setBaseGas(111, { from: bob })
            await relayManager.baseGas().then((res) => {
                expect(res.toString()).to.eq("111")
            })
        })
        it("setMinTransferAmount", async () => {
            await relayManager.setMinTransferAmount(112, { from: bob })
            await relayManager.minTransferAmount().then((res) => {
                expect(res.toString()).to.eq("112")
            })
        })
        describe("reverts if", async () => {
            it("withdrawAdminFee insuficient funds", async () => {
                adminFee = await relayManager.adminFeeAccumulated()
                await expectRevert(relayManager.withdrawAdminFee(carol, adminFee + 100, { from: bob }), "RelayManager2: INSUFFICIENT_ADMIN_FEE")
            })
            it("withdrawGasFee insuficient funds", async () => {
                gasFee = await relayManager.gasFeeAccumulated()
                await expectRevert(relayManager.withdrawGasFee(carol, gasFee + 100, { from: bob }), "RelayManager2: INSUFFICIENT_GAS_FEE")
            })
            it("non-owner call setMinTransferAmount", async () => {
                await expectRevert(relayManager.setMinTransferAmount(1, { from: carol }), "RelayManager2: CALLER_NO_OWNER")
            })
            it("non-owner call setAdminFee", async () => {
                await expectRevert(relayManager.setAdminFee(1, { from: carol }), "RelayManager2: CALLER_NO_OWNER")
            })
            it("non-owner call setBaseGas", async () => {
                await expectRevert(relayManager.setBaseGas(1, { from: carol }), "RelayManager2: CALLER_NO_OWNER")
            })
            it("non-owner call transferOwnership", async () => {
                await expectRevert(relayManager.transferOwnership(bob, { from: carol }), "RelayManager2: CALLER_NO_OWNER")
            })
            it("call transferOwnership with zero address", async () => {
                await expectRevert(relayManager.transferOwnership(constants.ZERO_ADDRESS, { from: bob }), "RelayManager2: INVALID_ADDRESS")
            })
            it("non owner call renounceOwnership", async () => {
                await expectRevert(relayManager.renounceOwnership({ from: carol }), "RelayManager2: CALLER_NO_OWNER")
            })
            it("non new owner call acceptOwnership", async () => {
                await relayManager.transferOwnership(alice, { from: bob })
                await expectRevert(relayManager.acceptOwnership({ from: carol }), "RelayManager2: CALLER_NO_NEW_OWNER")
                expectEvent(await relayManager.renounceOwnership({ from: bob }), "OwnershipTransferred")
            })
        })
    })
})
