const { ethers } = require("hardhat")
const { expect } = require("chai")

async function setup() {
    const StakeMath = await ethers.getContractFactory("StakeMathMock")
    return await StakeMath.deploy()
}

describe("StakeMath", async () => {
    let contract
    before(async () => {
        contract = await setup()
    })

    describe("StakeMath", async () => {
        it("multiplier", async () => {
            expect(await contract.multiplier(1)).to.eq(120)
            expect(await contract.multiplier(299)).to.eq(120)
            expect(await contract.multiplier(300)).to.eq(110)
            expect(await contract.multiplier(3000)).to.eq(110)
            expect(await contract.multiplier(3999)).to.eq(110)
            expect(await contract.multiplier(4000)).to.eq(100)
            expect(await contract.multiplier(5000)).to.eq(100)
        })
        it("boost", async () => {
            expect(await contract.boost(10)).to.eq(106)
            expect(await contract.boost(20)).to.eq(111)
            expect(await contract.boost(50)).to.eq(120)
            expect(await contract.boost(60)).to.eq(120)
        })
    })
})
