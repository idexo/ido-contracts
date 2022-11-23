const SPVDAO = artifacts.require("contracts/dao/SPVDAO.sol")
const StakePool = artifacts.require("StakePool")
const ERC20 = artifacts.require("ERC20Mock")

const { Contract } = require("@ethersproject/contracts")
const { expect } = require("chai")
const { BN, constants, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const { toWei } = require("web3-utils")
const time = require("./helpers/time")
const timeTraveler = require("ganache-time-traveler")

contract("Voting", async (accounts) => {
    let ido, spvdao
    const [alice, bob, carol] = accounts

    before(async () => {
        ido = await ERC20.new("Idexo Community", "IDO", { from: alice })
        spvdao = await SPVDAO.new("test", "T", "", 100, 1, ido.address, 15, 15, "description")
    })

    describe("#Inital tests", async () => {
        it("isHolder", async () => {
            expect(await spvdao.isHolder(bob)).to.eq(false)
        })
    })

    describe("#Get", async () => {
        it("getStakeAmount", async () => {
            expect(Number(await spvdao.getStakeAmount(bob))).to.eq(0)
        })
    })
})
