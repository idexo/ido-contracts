const Voting = artifacts.require('Voting');
const StakePool = artifacts.require('StakePool');
const ERC20 = artifacts.require('ERC20Mock');

const { Contract } = require('@ethersproject/contracts');
const { expect } = require('chai');
const {
  BN,
  constants,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');
const time = require('./helpers/time');
const timeTraveler = require('ganache-time-traveler');

const weiAmount = amount =>
  new BN(amount).mul(new BN(10).pow(new BN(18)));

contract('Voting', async accounts => {
  let ido, erc20;
  let voting, sPool1, sPool2, sPool3;
  const [alice, bob, carol] = accounts;

  beforeEach(async () => {
    ido = await ERC20.new('Idexo Community', 'IDO');
    erc20 = await ERC20.new('USD Tether', 'USDT');
    sPool1 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
    sPool2 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
    sPool3 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
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

  describe('#StakePool', async () => {
    beforeEach(async () => {
      await voting.addOperator(bob);
    });
    it('addStakePool', async () => {
      await voting.addStakePool(sPool3.address, {from: bob});
      await voting.getStakePools().then(res => {
        expect(res.length).to.eq(3);
        expect(res[0]).to.eq(sPool1.address);
        expect(res[1]).to.eq(sPool2.address);
        expect(res[2]).to.eq(sPool3.address);
      });
    });
    it('removeStakePool', async () => {
      await voting.removeStakePool(sPool2.address, {from: bob});
      await voting.getStakePools().then(res => {
        expect(res.length).to.eq(1);
        expect(res[0]).to.eq(sPool1.address);
      });
    });
    describe('reverts if', async () => {
      it('addStakePool removeStakePool', async () => {
        await expectRevert(
          voting.addStakePool(sPool3.address, {from: carol}),
          'Voting#onlyOperator: CALLER_NO_OPERATOR_ROLE'
        );
        await expectRevert(
          voting.addStakePool(constants.ZERO_ADDRESS, {from: bob}),
          'Voting#addStakePool: STAKE_POOL_ADDRESS_INVALID'
        );
        await expectRevert(
          voting.addStakePool(sPool2.address, {from: bob}),
          'Voting#addStakePool: STAKE_POOL_ADDRESS_ALREADY_FOUND'
        );
        await expectRevert(
          voting.removeStakePool(sPool3.address, {from: bob}),
          'Voting#removeStakePool: STAKE_POOL_ADDRESS_NOT_FOUND'
        );
      });
    });
  });

  describe('#Poll', async () => {
    beforeEach(async () => {
      await ido.mint(alice, weiAmount(10000000));
      await ido.mint(bob, weiAmount(10000000));
      await ido.approve(sPool1.address, weiAmount(10000000));
      await ido.approve(sPool2.address, weiAmount(10000000));
      await ido.approve(sPool1.address, weiAmount(10000000), {from: bob});
      await ido.approve(sPool2.address, weiAmount(10000000), {from: bob});
      await sPool1.deposit(weiAmount(4000));
      await sPool1.deposit(weiAmount(7000), {from: bob});
      await sPool2.deposit(weiAmount(8000));
      await sPool2.deposit(weiAmount(14000), {from: bob});
      await voting.addOperator(bob);
      await timeTraveler.advanceTime(time.duration.months(1));
    });
    it('createPoll castVote getWeight checkIfVoted endPoll', async () => {
      await voting.createPoll('Solana Integration', new BN(3), new BN(30), {from: bob});
      await voting.getPoll(1).then(res => {
        expect(res[0]).to.eq('Solana Integration');
        expect(res[2].sub(res[1]).toString()).to.eq(time.duration.days(3).toString());
        expect(res[3].toString()).to.eq('30');
        expect(res[4].toString()).to.eq('0');
        expect(res[5]).to.eq(bob);
      });
      await voting.getWeight.call(1, alice).then(res => {
        expect(res.toString()).to.eq('14400000000000000000000');
      });
      expect(await voting.checkIfVoted(1, alice)).to.eq(false);
      expectEvent(
        await voting.castVote(1, true, {from: alice}),
        'VoteCasted'
      );
      expect(await voting.checkIfVoted(1, alice)).to.eq(true);
      await voting.castVote(1, false, {from: bob});
      await voting.getPollForOperator(1, {from: bob}).then(res => {
        expect(res[7].toString()).to.eq('14400000000000000000000');
        expect(res[8].toString()).to.eq('25200000000000000000000');
      });
      await timeTraveler.advanceTime(time.duration.days(3));
      expectEvent(
        await voting.endPoll(1, {from: bob}),
        'PollStatusUpdated',
        {
          pollID: new BN(1),
          status: new BN(2)
        }
      );
    });
    describe('reverts if', async () => {
      it('createPoll', async () => {
        await expectRevert(
          voting.createPoll('Solana Integration', new BN(3), new BN(30), {from: carol}),
          'Voting#onlyOperator: CALLER_NO_OPERATOR_ROLE'
        );
        await expectRevert(
          voting.createPoll('', new BN(3), new BN(30), {from: bob}),
          'Voting#createPoll: DESCRIPTION_INVALID'
        );
        await expectRevert(
          voting.createPoll('Solana Integration', new BN(0), new BN(30), {from: bob}),
          'Voting#createPoll: DURATION_TIME_INVALID'
        );
        await voting.createPoll('Solana Integration', new BN(3), new BN(30), {from: bob});
        await expectRevert(
          voting.getPoll(2),
          'Voting#validPoll: POLL_ID_INVALID'
        );
        await expectRevert(
          voting.getWeight(1, constants.ZERO_ADDRESS),
          'Voting#getWeight: ACCOUNT_INVALID'
        );
        await expectRevert(
          voting.endPoll(1),
          'Voting#endPoll: VOTING_PERIOD_NOT_EXPIRED'
        );
        await voting.castVote(1, true, {from: alice});
        await expectRevert(
          voting.castVote(1, true, {from: alice}),
          'Voting#castVote: USER_ALREADY_VOTED'
        );
        await timeTraveler.advanceTime(time.duration.days(3));
        await voting.endPoll(1, {from: bob});
        await expectRevert(
          voting.castVote(1, true, {from: alice}),
          'Voting#castVote: POLL_ALREADY_ENDED'
        );
      });
    });
  });
});
