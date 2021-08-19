const { expect, assert} = require('chai');
const time = require('./helpers/time');
const timeTraveler = require('ganache-time-traveler');
const {
  BN,           // Big Number support
  constants,    // Common constants, like the zero address and largest integers
  expectEvent,  // Assertions for emitted events
  expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers');

const StakePool = artifacts.require('StakePool');
const ERC20 = artifacts.require('ERC20Mock');
const IDO = artifacts.require('IDO');

contract('::StakePool', async accounts => {
  let stakePool;
  let ido;
  let erc20;

  const [alice, bob, carl] = accounts;
  const stakeTokenName = 'Idexo Stake Token';
  const stakeTokenSymbol = 'IDS';
  const erc20Name = 'USD Tether';
  const erc20Symbol = 'USDT';
  const decimals = 18;

  before(async () => {
    ido = await IDO.new({from: alice});
    erc20 = await ERC20.new(erc20Name, erc20Symbol, {from: alice});
    stakePool = await StakePool.new(stakeTokenName, stakeTokenSymbol, ido.address, erc20.address, {from: alice});
    await stakePool.addOperator(bob);
  });

  describe('#Role', async () => {
    it ('should add operator', async () => {
      expect(await stakePool.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await stakePool.removeOperator(bob);
      expect(await stakePool.checkOperator(bob)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('add operator by non-admin', async () => {
        await expectRevert(
          stakePool.addOperator(bob, {from: bob}),
          'StakePool#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
      it('remove operator by non-admin', async () => {
        await stakePool.addOperator(bob);
        await expectRevert(
          stakePool.removeOperator(bob, {from: bob}),
          'StakePool#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
    });
  });

  describe('#Stake', async () => {
    before(async () => {
      await ido.mint(alice, web3.utils.toWei(new BN(20000)));
      await ido.approve(stakePool.address, web3.utils.toWei(new BN(20000)), {from: alice});
    });
    describe('##deposit', async () => {
      it('should deposit', async () => {
        await stakePool.deposit(web3.utils.toWei(new BN(5200)), {from: alice});
        await stakePool.getStakeInfo(1).then(res => {
          expect(res[0].toString()).to.eq('5200000000000000000000');
          expect(res[1].toString()).to.eq('120');
        });
        const aliceIDOBalance = await ido.balanceOf(alice);
        expect(aliceIDOBalance.toString()).to.eq('4800000000000000000000');
      });
      describe('reverts if', async () => {
        it('stake amount is lower than minimum amount', async () => {
          await expectRevert(
            stakePool.deposit(web3.utils.toWei(new BN(2300)), {from: alice}),
            'StakePool#deposit: UNDER_MINIMUM_STAKE_AMOUNT'
          );
        });
      });
    });
    describe('##withdraw', async () => {
      it('should withdraw', async () => {
        await stakePool.withdraw(1, web3.utils.toWei(new BN(2600)), {from: alice});
        await stakePool.getStakeInfo(1).then(res => {
          expect(res[0].toString()).to.eq('2600000000000000000000');
        });
        await stakePool.withdraw(1, web3.utils.toWei(new BN(2600)), {from: alice});
        await expectRevert(
          stakePool.getStakeInfo(1),
          'StakeToken#getStakeInfo: STAKE_NOT_FOUND'
        );
      });
      describe('reverts if', async () => {
        it('withdraw amount is lower than minimum amount', async () => {
          await stakePool.deposit(web3.utils.toWei(new BN(2800)), {from: alice});
          await expectRevert(
            stakePool.withdraw(2, web3.utils.toWei(new BN(2300)), {from: alice}),
            'StakePool#withdraw: UNDER_MINIMUM_STAKE_AMOUNT'
          );
        });
      });
    });
    describe('##getters', async () => {
      it('getStakeTokenIds, getStakeAmount, isHolder, getEligibleStakeAmount', async () => {
        await stakePool.deposit(web3.utils.toWei(new BN(3000)), {from: alice});
        await stakePool.getStakeTokenIds(alice).then(res => {
          expect(res.length).to.eq(2);
          expect(res[0].toString()).to.eq('2');
          expect(res[1].toString()).to.eq('3');
        });
        await stakePool.getStakeAmount(alice).then(res => {
          expect(res.toString()).to.eq('6960000000000000000000');
        });
        await stakePool.getStakeInfo(2).then(res => {
          expect(res[0]).to.eq('2800000000000000000000');
          expect(res[1]).to.eq('120');
        });
        expect(await stakePool.isHolder(alice)).to.eq(true);
        expect(await stakePool.isHolder(bob)).to.eq(false);
      });
    });
  });

  // describe('#Revenue Share', async () => {
  //   describe('##deposit', async () => {
  //     beforeEach(async () => {
  //       await erc20.mint(alice, new BN(10000).mul(new BN(10).pow(new BN(decimals))));
  //       await erc20.approve(stakePool.address, new BN(10000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
  //       // await stakePool.addOperator(alice);
  //     });
  //     it('should deposit', async () => {
  //       await stakePool.depositRevenueShare(new BN(4000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
  //       await erc20.balanceOf(alice).then(balance => {
  //         expect(balance.toString()).to.eq('6000000000000000000000');
  //       });
  //       await stakePool.getRevenueShareDeposit(0).then(res => {
  //         expect(res[0]).to.eq(alice);
  //         expect(res[1].toString()).to.eq('4000000000000000000000');
  //       });
  //     });
  //     describe('reverts if', async () => {
  //       it('deposit amount is 0', async () => {
  //         await expectRevert(
  //           stakePool.depositRevenueShare(new BN(0), {from: alice}),
  //           'StakePool#depositRevenueShare: ZERO_AMOUNT'
  //           );
  //         });
  //       });
  //   });
  //   describe('##distribute', async () => {
  //     beforeEach(async () => {
  //       // Deposit stake
  //       await erc20.mint(alice, new BN(20000).mul(new BN(10).pow(new BN(decimals))));
  //       await erc20.approve(stakePool.address, new BN(20000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
  //       await erc20.mint(bob, new BN(10000).mul(new BN(10).pow(new BN(decimals))));
  //       await erc20.approve(stakePool.address, new BN(10000).mul(new BN(10).pow(new BN(decimals))), {from: bob});
  //       await ido.mint(alice, new BN(10000).mul(new BN(10).pow(new BN(decimals))));
  //       await ido.approve(stakePool.address, new BN(10000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
  //       await ido.mint(bob, new BN(10000).mul(new BN(10).pow(new BN(decimals))));
  //       await ido.approve(stakePool.address, new BN(10000).mul(new BN(10).pow(new BN(decimals))), {from: bob});
  //       // await stakePool.addOperator(alice);
  //     });
  //     it('distribute', async () => {
  //       // After 5 days
  //       timeTraveler.advanceTime(time.duration.days(5));
  //       await stakePool.deposit(new BN(3000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
  //       // After 1 day
  //       timeTraveler.advanceTime(time.duration.days(1));
  //       await stakePool.deposit(new BN(6000).mul(new BN(10).pow(new BN(decimals))), {from: bob});
  //       // After 10 days
  //       timeTraveler.advanceTime(time.duration.days(10));
  //       await stakePool.depositRevenueShare(new BN(4000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
  //       // After 1 day
  //       timeTraveler.advanceTime(time.duration.days(1));
  //       await stakePool.depositRevenueShare(new BN(4500).mul(new BN(10).pow(new BN(decimals))), {from: alice});
  //       // After 15 days (1 month passed)
  //       timeTraveler.advanceTime(time.duration.days(15));
  //       expectEvent(
  //         await stakePool.distribute({from: alice}),
  //         'MonthlyDistributed',
  //         {
  //           amount: new BN(0),
  //         }
  //       );

  //       // After 10 days
  //       timeTraveler.advanceTime(time.duration.days(10));
  //       await stakePool.depositRevenueShare(new BN(4000).mul(new BN(10).pow(new BN(decimals))), {from: alice});
  //       // After 11 days
  //       timeTraveler.advanceTime(time.duration.days(11));
  //       await stakePool.depositRevenueShare(new BN(4500).mul(new BN(10).pow(new BN(decimals))), {from: alice});
  //       // After 21 days (2 months passed)
  //       timeTraveler.advanceTime(time.duration.days(15));
  //       expectEvent(
  //         await stakePool.distribute({from: alice}),
  //         'MonthlyDistributed',
  //         {
  //           amount: new BN(2122875).mul(new BN(10).pow(new BN(15))),
  //         }
  //       );
  //       await stakePool.getUnlockedRevenueShare().then(res => {
  //         expect(res.toString()).to.eq('707625000000000000000');
  //       });
  //       await stakePool.getUnlockedRevenueShare({from: bob}).then(res => {
  //         expect(res.toString()).to.eq('1415250000000000000000');
  //       });
  //       expectEvent(
  //         await stakePool.withdrawRevenueShare(new BN(700).mul(new BN(10).pow(new BN(decimals))), {from: alice}),
  //         'RevenueShareWithdrawn'
  //       );
  //       await stakePool.getUnlockedRevenueShare().then(res => {
  //         expect(res.toString()).to.eq('7625000000000000000');
  //       });
  //     });
  //   });
  // });
});
