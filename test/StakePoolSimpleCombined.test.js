const { expect } = require('chai');
const { BN, expectEvent } = require('@openzeppelin/test-helpers');
const StakePool = artifacts.require('contracts/staking/StakePoolSimpleCombined.sol:StakePoolSimpleCombined');
const ERC20 = artifacts.require('ERC20Mock');

contract('::StakePoolSimpleCombined', async accounts => {
  let stakePool, ido, erc20;
  const [alice, bob, carol] = accounts;

  before(async () => {
    ido = await ERC20.new('Idexo Community', 'IDO');
    erc20 = await ERC20.new('USD Tether', 'USDT');
    stakePool = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address, {from: alice});
    await stakePool.addOperator(bob);
  });

  describe('# Stake', async () => {
    before(async () => {
      await ido.mint(alice, web3.utils.toWei(new BN(20000)));
      await ido.approve(stakePool.address, web3.utils.toWei(new BN(20000)), {from: alice});
    });

    describe('## deposit', async () => {
      it('should deposit', async () => {
        expectEvent(
          await stakePool.deposit(web3.utils.toWei(new BN(5200)), {from: alice}),
          'Deposited'
        );
        await stakePool.getStakeInfo(1).then(res => {
          expect(res[0].toString()).to.eq('5200000000000000000000');
        });
      });
    });

    describe('## withdraw', async () => {
      it('should withdraw', async () => {
        expectEvent(
          await stakePool.withdraw(1, web3.utils.toWei(new BN(2600)), {from: alice}),
          'StakeAmountDecreased'
        );
        await stakePool.getStakeInfo(1).then(res => {
          expect(res[0].toString()).to.eq('2600000000000000000000');
        });
      });
    });

    describe('## transfer', async () => {
        it('should transfer', async () => {
          expectEvent(
            await stakePool.transferFrom(alice, carol, 1, {from: alice}),
            'Transfer'
          );
          await stakePool.getStakeInfo(1).then(res => {
            expect(res[0].toString()).to.eq('2600000000000000000000');
          });
        });
      });
  });

});
