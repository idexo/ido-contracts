const { expect } = require("chai")  
const { duration } = require("./helpers/time")  
const timeTraveler = require("ganache-time-traveler")  
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")  
const StakePool = artifacts.require("contracts/staking/StakePoolMultRewardsTimeLimited.sol:StakePoolMultRewardsTimeLimited")  
const ERC20 = artifacts.require("ERC20Mock")  
  
contract("::StakePoolMultRewardsTimeLimited", async (accounts) => {  
    let stakePool, ido, usdt, usdc  
    const [owner, alice, bob, carol, darren] = accounts  
    const DOMAIN = "https://idexo.com/"  
  
    before(async () => {  
        const minPoolStakeAmount = web3.utils.toWei(new BN(10000))  
        ido = await ERC20.new("Idexo Community", "IDO", { from: owner })  
        usdt = await ERC20.new("USD Tether", "USDT", { from: owner })  
        usdc = await ERC20.new("USDC Coin", "USDC", { from: owner })  
        stakePool = await StakePool.new("Idexo Stake Token", "IDS", DOMAIN, 1, minPoolStakeAmount, ido.address, usdt.address, { from: owner })  
    })  
  
    describe("# Get Contract info", async () => {  
        it("should get timeLimitInDays", async () => {  
            await stakePool.timeLimitInDays().then((res) => {  
                expect(res.toString()).to.eq("1")  
            })  
        })  
        it("should get minPoolStakeAmount", async () => {  
            await stakePool.minPoolStakeAmount().then((res) => {  
                expect(res.toString()).to.eq(web3.utils.toWei(new BN(10000)).toString())  
            })  
        })  
        it("should get timeLimit", async () => {  
            await stakePool.timeLimit().then((res) => {  
                expect(res.toString()).to.eq("0")  
            })  
        })  
        it("should get depositToken", async () => {  
            await stakePool.depositToken().then((res) => {  
                expect(res.toString()).to.eq(ido.address)  
            })  
        })  
    })  
  
    describe("# Staking", async () => {  
        before(async () => {  
            for (const user of [alice, bob, carol, darren]) {  
                await ido.mint(user, web3.utils.toWei(new BN(20000)))  
                await ido.approve(stakePool.address, web3.utils.toWei(new BN(20000)), { from: user })  
            }  
        })  
  
        describe("staking", async () => {  
            it("should stake 1", async () => {  
                await stakePool.getEligibleStakeAmount(0, { from: alice }).then((res) => {  
                    expect(res.toString()).to.eq("0")  
                })  
                await stakePool.isHolder(alice).then((res) => {  
                    expect(res.toString()).to.eq("false")  
                })  
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(500)), 0, { from: alice }), "Deposited")  
                await ido.balanceOf(stakePool.address).then((res) => {  
                    expect(res.toString()).to.eq("500000000000000000000")  
                })  
                await stakePool.getStakeInfo(1).then((res) => {  
                    expect(res[0].toString()).to.eq("500000000000000000000")  
                })  
            })  
            it("should stake 2", async () => {  
                await stakePool.getEligibleStakeAmount(0, { from: carol }).then((res) => {  
                    expect(res.toString()).to.eq("0")  
                })  
                let number = await web3.eth.getBlockNumber()  
                let block = await web3.eth.getBlock(number)  
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }), "Deposited")  
                await stakePool.getStakeInfo(2).then((res) => {  
                    expect(res[0].toString()).to.eq("5000000000000000000000")  
                })  
                await stakePool.isHolder(carol).then((res) => {  
                    expect(res.toString()).to.eq("true")  
                })  
                await timeTraveler.advanceTime(duration.months(10))  
                await stakePool.getEligibleStakeAmount(block.timestamp, { from: carol }).then((res) => {  
                    expect(res.toString()).to.not.eq("0")  
                })  
                await timeTraveler.advanceTime(duration.months(-10))  
            })  
            it("should stake 3", async () => {  
                await stakePool.getEligibleStakeAmount(0, { from: carol }).then((res) => {  
                    expect(res.toString()).to.eq("0")  
                })  
                let number = await web3.eth.getBlockNumber()  
                let block = await web3.eth.getBlock(number)  
                expectEvent(await stakePool.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }), "Deposited")  
                await stakePool.getStakeInfo(3).then((res) => {  
                    expect(res[0].toString()).to.eq("5000000000000000000000")  
                })  
                await stakePool.isHolder(carol).then((res) => {  
                    expect(res.toString()).to.eq("true")  
                })  
                await timeTraveler.advanceTime(duration.months(10))  
                await stakePool.getEligibleStakeAmount(block.timestamp, { from: carol }).then((res) => {  
                    expect(res.toString()).to.not.eq("0")  
                })  
                await timeTraveler.advanceTime(duration.months(-10))  
            })  
  
            describe("should withdraw before and after pool closed", async () => {  
                let snapshotId;  
                  
                beforeEach(async () => {  
                    // Take a fresh snapshot before each test  
                    snapshotId = await timeTraveler.takeSnapshot();  
                });  
                  
                afterEach(async () => {  
                    // Revert to the snapshot after each test  
                    await timeTraveler.revertToSnapshot(snapshotId);  
                });  
                  
                it("should withdraw stake 3 before", async () => {  
                    // Log initial pool balance  
                    const balanceBefore = await ido.balanceOf(stakePool.address);  
                    console.log("Pool balance before withdrawal:", balanceBefore.toString());  
                      
                    // Check time limit status  
                    const timeLimit = await stakePool.timeLimit();  
                    console.log("Time limit before withdrawal:", timeLimit.toString());  
                      
                    // Execute withdrawal  
                    const tx = await stakePool.withdraw(3, web3.utils.toWei(new BN(5000)), { from: carol });  
                    expectEvent(tx, "Withdrawn");  
                      
                    // Check balance after withdrawal  
                    const balanceAfter = await ido.balanceOf(stakePool.address);  
                    console.log("Pool balance after withdrawal:", balanceAfter.toString());  
                      
                    // Check ownership status  
                    await stakePool.isHolder(carol).then((res) => {  
                        expect(res.toString()).to.eq("true");  
                    });  
                      
                    // Verify time limit is still 0  
                    await stakePool.timeLimit().then((res) => {  
                        expect(res.toString()).to.eq("0");  
                    });  
                      
                    // Verify the difference is exactly 5000 tokens  
                    const difference = balanceBefore.sub(balanceAfter);  
                    console.log("Withdrawal difference:", difference.toString());  
                    expect(difference.toString()).to.eq(web3.utils.toWei(new BN(5000)).toString());  
                });  
                  
                it("should stake 4", async () => {  
                    // Log initial state  
                    console.log("Initial time limit:", (await stakePool.timeLimit()).toString());  
                    const initialBalance = await ido.balanceOf(stakePool.address);  
                    console.log("Initial pool balance:", initialBalance.toString());  
                      
                    // Execute deposit  
                    const tx = await stakePool.deposit(web3.utils.toWei(new BN(600)), 0, { from: darren });  
                    expectEvent(tx, "Deposited");  
                      
                    // Verify deposit succeeded  
                    const finalBalance = await ido.balanceOf(stakePool.address);  
                    console.log("Final pool balance:", finalBalance.toString());  
                      
                    // Check difference  
                    const difference = finalBalance.sub(initialBalance);  
                    expect(difference.toString()).to.eq(web3.utils.toWei(new BN(600)).toString());  
                });  
                  
                it("should withdraw stake 5 after pool closed", async () => {  
                    // Log initial state  
                    const initialBalance = await ido.balanceOf(stakePool.address);  
                    console.log("Initial pool balance:", initialBalance.toString());  
                      
                    // First deposit  
                    const depositTx = await stakePool.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol });  
                    expectEvent(depositTx, "Deposited");  
                      
                    // Get token ID  
                    const tokenId = depositTx.logs.find(log => log.event === 'Deposited').args.stakeId;  
                    console.log("New stake token ID:", tokenId.toString());  
                      
                    // Get current block time and timeLimit  
                    const blockNum = await web3.eth.getBlockNumber();  
                    const block = await web3.eth.getBlock(blockNum);  
                    console.log("Current block timestamp:", block.timestamp);  
                    console.log("Time limit before advancing:", (await stakePool.timeLimit()).toString());  
                      
                    // Advance time by more than the time limit (1 day)  
                    await timeTraveler.advanceTimeAndBlock(duration.days(2));  
                      
                    // Verify time has advanced  
                    const newBlockNum = await web3.eth.getBlockNumber();  
                    const newBlock = await web3.eth.getBlock(newBlockNum);  
                    console.log("New block timestamp:", newBlock.timestamp);  
                    console.log("Time difference:", newBlock.timestamp - block.timestamp);  
                      
                    // Check if time limit is set now  
                    const timeLimit = await stakePool.timeLimit();  
                    console.log("Time limit after advancing:", timeLimit.toString());  
                      
                    // Withdraw should still work even if deposits are closed  
                    const withdrawTx = await stakePool.withdraw(tokenId, web3.utils.toWei(new BN(5000)), { from: carol });  
                    expectEvent(withdrawTx, "Withdrawn");  
                      
                    // Verify time limit is still set  
                    await stakePool.timeLimit().then((res) => {  
                        console.log("Time limit after withdrawal:", res.toString());  
                        expect(res.toString()).to.not.eq("0");  
                    });  
                      
                    // Check final balance  
                    const finalBalance = await ido.balanceOf(stakePool.address);  
                    console.log("Final pool balance:", finalBalance.toString());  
                });  
            });  
  
            describe("should revert stake after pool closed", async () => {  
                let snapshotId;  
                  
                before(async () => {  
                    // Take a fresh snapshot  
                    snapshotId = await timeTraveler.takeSnapshot();  
                      
                    // Get initial balance  
                    const balance = await ido.balanceOf(stakePool.address);  
                    console.log("Initial pool balance before time advance:", balance.toString());  
                      
                    // Check time limit  
                    const initialTimeLimit = await stakePool.timeLimit();  
                    console.log("Initial time limit:", initialTimeLimit.toString());  
                      
                    // Get current time  
                    const blockNum = await web3.eth.getBlockNumber();  
                    const block = await web3.eth.getBlock(blockNum);  
                    console.log("Current timestamp before advance:", block.timestamp);  
                      
                    // Advance time to close the pool  
                    await timeTraveler.advanceTimeAndBlock(duration.days(2));  
                      
                    // Get new time  
                    const newBlockNum = await web3.eth.getBlockNumber();  
                    const newBlock = await web3.eth.getBlock(newBlockNum);  
                    console.log("Current timestamp after advance:", newBlock.timestamp);  
                    console.log("Time advanced by:", newBlock.timestamp - block.timestamp);  
                      
                    // Verify pool is closed  
                    const timeLimit = await stakePool.timeLimit();  
                    console.log("Time limit after advancing:", timeLimit.toString());  
                });  
                  
                after(async () => {  
                    // Revert after the tests  
                    await timeTraveler.revertToSnapshot(snapshotId);  
                });  
                  
                it("should revert stake 5 if DEPOSIT_TIME_CLOSED", async () => {  
                    // Check current balance  
                    const balance = await ido.balanceOf(stakePool.address);  
                    console.log("Pool balance before attempted deposit:", balance.toString());  
                      
                    // Check time limit  
                    const timeLimit = await stakePool.timeLimit();  
                    console.log("Current time limit:", timeLimit.toString());  
                      
                    // Attempt to stake should fail now  
                    await expectRevert(  
                        stakePool.deposit(web3.utils.toWei(new BN(5000)), 0, { from: carol }),  
                        "StakePool#_deposit: DEPOSIT_TIME_CLOSED"  
                    );  
                      
                    // Verify balance hasn't changed  
                    const balanceAfter = await ido.balanceOf(stakePool.address);  
                    console.log("Pool balance after failed deposit:", balanceAfter.toString());  
                    expect(balanceAfter.toString()).to.eq(balance.toString());  
                });  
            });  
        });  
    });  
});  