const { Contract } = require('@ethersproject/contracts');
const { expect } = require('chai');
const {
  BN,
  constants,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');

const Voting = artifacts.require('Voting');
const StakePool = artifacts.require('StakePool');
const ERC20 = artifacts.require('ERC20Mock');

const weiAmount = amount =>
  new BN(amount).mul(new BN(10).pow(new BN(18)));

contract('Voting', async accounts => {
  let ido, erc20;
  let voting, sPool1, sPool2;
  const [alice, bob, carol] = accounts;

  beforeEach(async () => {
    ido = await ERC20.new('Idexo Community', 'IDO');
    erc20 = await ERC20.new('USD Tether', 'USDT');
    sPool1 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
    sPool2 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
    voting = await Voting.new([sPool1.address, sPool2.address]);
  });

  describe('#Role', async () => {
    it ('should add operator', async () => {
      await voting.addOperator(bob);
      expect(await voting.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await voting.addOperator(bob);
      await voting.removeOperator(bob);
      expect(await voting.checkOperator(bob)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('add operator by non-admin', async () => {
        await expectRevert(
          voting.addOperator(bob, {from: bob}),
          'Voting#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
      it('remove operator by non-admin', async () => {
        await voting.addOperator(bob);
        await expectRevert(
          voting.removeOperator(bob, {from: bob}),
          'Voting#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
    });
  });

  describe('#Poll', async () => {
    beforeEach(async () => {
      await voting.addOperator(bob);
    });
    it('createPoll', async () => {
      await voting.createPoll('Solana Integration', );
    });
  });
});
