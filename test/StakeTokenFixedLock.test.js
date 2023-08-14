const StakeTokenFixedLock = artifacts.require("StakeTokenFixedLock");
const ERC20Mock = artifacts.require("ERC20Mock"); // Mock ERC20 for testing
const { BN, constants, ether, expectEvent, expectRevert, time  } = require("@openzeppelin/test-helpers");

contract("StakeTokenFixedLock", ([deployer, user1, user2]) => {
    let stakingToken, stakingContract;


    beforeEach(async () => {
        // deploy mock ERC20 token and the staking contract
        stakingToken = await ERC20Mock.new("Mock Token", "MKT", { from: user1 });
        stakingContract = await StakeTokenFixedLock.new("Stake Token", "STK", "someBaseUri", stakingToken.address);
        
        // transfer some tokens to user1 for staking
        await stakingToken.mint(user1, web3.utils.toWei("100000"), { from: user1 });

        // transfer some tokens to user2 for depositing rewards
        await stakingToken.mint(user2, web3.utils.toWei("100000"), { from: user1 });
    });


    it('should correctly return staked amount and dispense reward after withdrawing', async () => {
        const stakeAmount = web3.utils.toWei(new BN(20000))
        const stakePeriod = 90; // days
        await stakingToken.mint(user1, web3.utils.toWei(new BN(20000)))
        await stakingToken.mint(user2, web3.utils.toWei(new BN(100000)))
        await stakingToken.approve(stakingContract.address, web3.utils.toWei(new BN(20000)), { from: user1 })
        await stakingContract.stake(web3.utils.toWei(new BN(20000)), stakePeriod, { from: user1 });

        await stakingToken.approve(stakingContract.address, web3.utils.toWei(new BN(50000)), { from: user2 })
        await stakingContract.depositReward(web3.utils.toWei(new BN(50000)), { from: user2 });

        // Fast forward time to 90 days
        await time.increase(time.duration.days(90));

        const timeDiff = new BN(90).mul(new BN(24)).mul(new BN(3600));
        const YEAR = new BN(365).mul(new BN(24)).mul(new BN(3600));
        const rate = new BN(5);


        const tokenId = 1; // Assuming the tokenId starts from 1

        // Calculate user's initial balance
        const initialBalance = await stakingToken.balanceOf(user1);

        // Let's assume for this test, the reward is calculated based on a simple formula.
        // You'll need to replace this with how rewards are calculated in your contract.
        const expectedReward = stakeAmount.mul(rate).mul(timeDiff).div(YEAR).div(new BN(100));

        await stakingContract.withdraw(tokenId, { from: user1 });
        const finalBalance = await stakingToken.balanceOf(user1);
        const tolerance = expectedReward.mul(new BN('1')).div(new BN('1000'));
        const finalTotal = initialBalance.add(stakeAmount).add(expectedReward)
        const difference = finalBalance - finalTotal

        // Convert raw numbers to BN instances if necessary
        const differenceBN = new BN(difference);
        const toleranceBN = new BN(tolerance);

        // Validate final balance is as expected: initial + stakeAmount + expectedReward, within tolerance range
        expect(differenceBN).to.be.bignumber.lte(toleranceBN);
    });


    it("should stake tokens", async () => {
        // user1 approves staking contract to spend his tokens
        await stakingToken.mint(user1, web3.utils.toWei("5000"))
        await stakingToken.approve(stakingContract.address, web3.utils.toWei("5000"), { from: user1 });

        // user1 stakes tokens for 45 days
        await stakingContract.stake(web3.utils.toWei("5000"), 45, { from: user1 });

        const stakeInfo = await stakingContract.getStakeInfo(1);
        assert(stakeInfo.amount.toString() === web3.utils.toWei("5000"));
    });

    it('should calculate rewards correctly after staking', async () => {
        const stakeAmount = web3.utils.toWei(new BN(20000))
        const stakePeriod = 90; // days

        // Calculate expected rate based on period
        let rate;
        if (stakePeriod === 45) {
            rate = 2;
        } else if (stakePeriod === 60) {
            rate = 3;
        } else if (stakePeriod === 90) {
            rate = 5;
        } else {
            assert.fail('Unsupported staking period used in test');
        }
        rate = new BN(rate);

        await stakingToken.mint(user1, web3.utils.toWei(new BN(20000)))
        await stakingToken.mint(user2, web3.utils.toWei(new BN(20000)))
        await stakingToken.approve(stakingContract.address, web3.utils.toWei(new BN(20000)), { from: user1 });
        await stakingToken.approve(stakingContract.address, web3.utils.toWei(new BN(20000)), { from: user2 });

        await stakingContract.stake(stakeAmount, stakePeriod, { from: user1 });
        await stakingContract.depositReward(stakeAmount,{ from: user2 });

        // Fast forward time to 90 days
        await time.increase(time.duration.days(90));
        const timeDiff = new BN(90).mul(new BN(24)).mul(new BN(3600));
        const YEAR = new BN(365).mul(new BN(24)).mul(new BN(3600));

        const expectedReward = stakeAmount.mul(rate).mul(timeDiff).div(YEAR).div(new BN(100));
        const tokenId = 1; // Assuming the tokenId starts from 1

        // Calculate user's initial balance
        const initialBalance = await stakingToken.balanceOf(user1);

        await stakingContract.claim(tokenId, { from: user1 });
        const finalBalance = await stakingToken.balanceOf(user1);
        const tolerance = expectedReward.mul(new BN('1')).div(new BN('1000'));
        const finalTotal = initialBalance.add(expectedReward)
        const difference = finalTotal.sub(finalBalance);

        // Convert raw numbers to BN instances if necessary
        // const differenceBN = new BN(difference);
        const toleranceBN = new BN(tolerance);

        // Validate final balance is as expected: initial + stakeAmount + expectedReward, within tolerance range
        expect(difference).to.be.bignumber.lte(toleranceBN);
    });

    it('should deposit rewards correctly', async () => {
        await stakingToken.mint(user1, ether("500"))
        const rewardAmount = ether('500');
        await stakingToken.approve(stakingContract.address, rewardAmount, { from: user1 })
        
        await stakingContract.depositReward(rewardAmount, { from: user1 });
        const contractRewardBalance = await stakingContract.availableRewards();

        expect(contractRewardBalance).to.be.bignumber.equal(rewardAmount);
    });

    it("should allow claiming rewards", async () => {
        await stakingToken.mint(user1, web3.utils.toWei("10000"))
        await stakingToken.mint(user2, web3.utils.toWei("10000"))
        await stakingToken.approve(stakingContract.address, web3.utils.toWei("5000"), { from: user1 });
        await stakingToken.approve(stakingContract.address, web3.utils.toWei("5000"), { from: user2 });
        await stakingContract.stake(web3.utils.toWei("5000"), 45, { from: user1 });
        await stakingContract.depositReward(web3.utils.toWei("5000"), { from: user2 });

        await time.increase(time.duration.days(30));

        await stakingContract.claim(1, { from: user1 });
        
        const userBalance = await stakingToken.balanceOf(user1);
        assert(userBalance.gt(web3.utils.toWei("5000")), "User balance should increase after claiming rewards");
    });

    it("should not allow withdrawing before staking period ends", async () => {
        await stakingToken.mint(user1, web3.utils.toWei("10000"))
        await stakingToken.approve(stakingContract.address, web3.utils.toWei("5000"), { from: user1 });
        await stakingContract.stake(web3.utils.toWei("5000"), 45, { from: user1 });

        await time.increase(time.duration.days(30));
        
        await expectRevert(
            stakingContract.withdraw(1, { from: user1 }),
            "STAKE_TOKEN_FIXED_LOCK#Staking_period_not_passed"
        );
    });

    it("should allow withdrawing after staking period ends", async () => {
        await stakingToken.mint(user1, web3.utils.toWei("10000"))
        await stakingToken.approve(stakingContract.address, web3.utils.toWei("10000"), { from: user1 });
        await stakingContract.stake(web3.utils.toWei("5000"), 45, { from: user1 });
        await stakingContract.depositReward(web3.utils.toWei("5000"), { from: user1 });

        await time.increase(time.duration.days(46));

        await stakingContract.withdraw(1, { from: user1 });
        const userBalance = await stakingToken.balanceOf(user1);
        assert(userBalance.gt(web3.utils.toWei("5000")), "User balance should increase after withdrawing rewards");
    });
});
