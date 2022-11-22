const { expect } = require("chai")
const { ethers } = require("hardhat")

const contractName = "UncappedSBTCommunityRecovery"

describe(`::Contract -> ${contractName}`, () => {
    const name = "SBT Community Recovery"
    const symbol = "SBTCR"
    const baseURI = ""
    let contract
    let deployer, alice, bob, carol, darren
    before(async () => {
        const Contract = await ethers.getContractFactory(contractName)
        const signers = await ethers.getSigners()

        contract = await Contract.deploy(name, symbol, baseURI)
        ;[deployer, alice, bob, carol, darren] = signers
    })

    describe("# Role", async () => {
        it("should add operator", async () => {
            await contract.addOperator(alice.address)
            expect(await contract.checkOperator(alice.address)).to.eq(true)
        })
        it("should add description", async () => {
            await contract.connect(alice).addDescription("test")
            expect(await contract.collectionDescription()).to.eq("test")
        })

        it("should remove operator", async () => {
            await contract.removeOperator(alice.address)
            expect(await contract.checkOperator(alice.address)).to.eq(false)
        })
        it("supportsInterface", async () => {
            await contract.supportsInterface(`0x00000000`).then((res) => {
                expect(res).to.eq(false)
            })
        })
        it("getCollectionIds", async () => {
            await contract.getCollectionIds(alice.address).then((res) => {
                expect(res.length).to.eq(0)
            })
        })

        describe("reverts if", async () => {
            it("add operator by NO-OWNER", async () => {
                await expect(contract.connect(alice).addOperator(bob.address)).to.be.revertedWith("Ownable: caller is not the owner")
            })
            it("remove operator by NO-OWNER", async () => {
                await contract.addOperator(bob.address)
                await expect(contract.connect(alice).removeOperator(bob.address)).to.be.revertedWith("Ownable: caller is not the owner")
            })
        })
    })

    describe("# Get Contract info", async () => {
        it("should get name", async () => {
            await contract.name().then((res) => {
                expect(res.toString()).to.eq(name)
            })
        })
    })

    describe("# Mint for accounts", async () => {
        it("mint Soulbound NFTs", async () => {
            const defaultTokenURI = "https://idexo.com"
            await contract.mintNFT(alice.address, defaultTokenURI)
            await contract.mintNFT(bob.address, defaultTokenURI)
            await contract.mintNFT(carol.address, defaultTokenURI)
            await contract.mintNFT(alice.address, defaultTokenURI)

            expect(await contract.balanceOf(alice.address)).to.equal(2)

            expect(await contract.isHolder(bob.address)).to.equal(true)
        })
    })

    describe("# Operators", async () => {
        it("should add new operators", async () => {
            await contract.connect(alice).addOperatorAsOwner(1, bob.address)
            await contract.connect(alice).addOperatorAsOwner(1, carol.address)
            await contract.connect(alice).addOperatorAsOwner(1, darren.address)

            await contract.connect(alice).addOperatorAsOwner(4, bob.address)
            await contract.connect(alice).addOperatorAsOwner(4, carol.address)
            await contract.connect(alice).addOperatorAsOwner(4, darren.address)

            await contract.connect(bob).addOperatorAsOwner(2, alice.address)
            await contract.connect(bob).addOperatorAsOwner(2, carol.address)
            await contract.connect(bob).addOperatorAsOwner(2, darren.address)

            await contract.connect(carol).addOperatorAsOwner(3, darren.address)

            expect(await contract.isOperator(bob.address, 1)).to.equal(true)
            expect(await contract.isOperator(darren.address, 3)).to.equal(true)
        })

        describe("## Revert if", async () => {
            it("not owner", async () => {
                await expect(contract.addOperatorAsOwner(1, bob.address)).to.revertedWith("ONLY_OWNER_CAN_ADD_INITIAL_OPERATORS")
            })
        })
    })

    describe("# Transfers", async () => {
        it("init a transfer", async () => {
            await contract.connect(bob).initiateTransfer(alice.address, darren.address, 1)
            await contract.connect(alice).initiateTransfer(bob.address, darren.address, 2)
            await contract.connect(darren).initiateTransfer(alice.address, carol.address, 4)
        })

        it("approve a transfer", async () => {
            await contract.connect(carol).approveTransfer(1)
            await contract.connect(darren).approveTransfer(2)
        })

        it("should transfer", async () => {
            await contract.connect(deployer).finalizeTransfer(1)
            await contract.connect(deployer).finalizeTransfer(2)
        })

        it("should disapproveTransfer", async () => {
            await contract.connect(bob).disapproveTransfer(4)
        })

        describe("## Revert if", async () => {
            it("not approved", async () => {
                await expect(contract.connect(deployer).finalizeTransfer(3)).to.revertedWith("NO_PENDING_TRANSFER")
            })
            it("not operator", async () => {
                await expect(contract.connect(carol).finalizeTransfer(4)).to.revertedWith("Operatorable: CALLER_NO_OPERATOR_ROLE")
            })
            it("already approved", async () => {
                await expect(contract.connect(darren).approveTransfer(4)).to.revertedWith("ALREADY_APPROVED_CURRENT_TRANSFER")
            })
        })
    })

    describe("# Locked transfers", async () => {
        // it("try transfer", async () => {
        //     await contract.connect(carol).transferFrom(carol.address, alice.address, 3)

        //     await contract.balanceOf(alice.address).then((res) => {
        //         expect(res).to.equal(2)
        //     })
        // })

        describe("## Revert if", async () => {
            it("not approved", async () => {
                await expect(contract.connect(carol).transferFrom(carol.address, alice.address, 3)).to.revertedWith(
                    "TRANSFER_LOCKED_ON_SBT_UNLESS_AUTHORIZED"
                )
            })
            it("call disapproveTransfer with nothing pending", async () => {
                await expect(contract.connect(carol).disapproveTransfer(1)).to.revertedWith(
                    "NO_PENDING_TRANSFER"
                )
            })
        })
    })

    describe("# History", async () => {
        it("get tokenInfo", async () => {
            await contract
                .connect(carol)
                .tokenInfos(1)
                .then((res) => {
                    console.log(res)
                })
        })
        it("get tokenHistory", async () => {
            await contract
                .connect(carol)
                .getHistory(1)
                .then((res) => {
                    console.log(res)
                })
        })

        // describe("## Revert if", async () => {
        //     it("not approved", async () => {
        //         await expect(contract.connect(carol).transferFrom(carol.address, alice.address, 3)).to.revertedWith(
        //             "TRANSFER_LOCKED_ON_SBT_UNLESS_AUTHORIZED"
        //         )
        //     })
        // })
    })
})
