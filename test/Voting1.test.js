const Voting1 = artifacts.require('Voting1');
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

contract('Voting1', async accounts => {
  let ido, erc20;
  let voting1, sPool1, sPool2, sPool3;
  const [alice, bob, carol] = accounts;

  beforeEach(async () => {
    ido = await ERC20.new('Idexo Community', 'IDO');
    erc20 = await ERC20.new('USD Tether', 'USDT');
    sPool1 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
    sPool2 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
    sPool3 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
    voting1 = await Voting1.new([sPool1.address, sPool2.address], weiAmount(400000), new BN(7), new BN(14));
  });

  describe('#Role', async () => {
    it ('should add operator', async () => {
      await voting1.addOperator(bob);
      expect(await voting1.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await voting1.addOperator(bob);
      await voting1.removeOperator(bob);
      expect(await voting1.checkOperator(bob)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('add operator by non-admin', async () => {
        await expectRevert(
          voting1.addOperator(bob, {from: bob}),
          'Voting1#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
      it('remove operator by non-admin', async () => {
        await voting1.addOperator(bob);
        await expectRevert(
          voting1.removeOperator(bob, {from: bob}),
          'Voting1#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
    });
  });

  describe('#StakePool', async () => {
    beforeEach(async () => {
      await voting1.addOperator(bob);
    });
    it('addStakePool', async () => {
      await voting1.addStakePool(sPool3.address, {from: bob});
      await voting1.getStakePools().then(res => {
        expect(res.length).to.eq(3);
        expect(res[0]).to.eq(sPool1.address);
        expect(res[1]).to.eq(sPool2.address);
        expect(res[2]).to.eq(sPool3.address);
      });
    });
    it('removeStakePool', async () => {
      await voting1.removeStakePool(sPool2.address, {from: bob});
      await voting1.getStakePools().then(res => {
        expect(res.length).to.eq(1);
        expect(res[0]).to.eq(sPool1.address);
      });
    });
    describe('reverts if', async () => {
      it('addStakePool removeStakePool', async () => {
        await expectRevert(
          voting1.addStakePool(sPool3.address, {from: carol}),
          'Voting1#onlyOperator: CALLER_NO_OPERATOR_ROLE'
        );
        await expectRevert(
          voting1.addStakePool(constants.ZERO_ADDRESS, {from: bob}),
          'Voting1#addStakePool: STAKE_POOL_ADDRESS_INVALID'
        );
        await expectRevert(
          voting1.addStakePool(sPool2.address, {from: bob}),
          'Voting1#addStakePool: STAKE_POOL_ADDRESS_ALREADY_FOUND'
        );
        await expectRevert(
          voting1.removeStakePool(sPool3.address, {from: bob}),
          'Voting1#removeStakePool: STAKE_POOL_ADDRESS_NOT_FOUND'
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
      await voting1.addOperator(bob);
      await timeTraveler.advanceTime(time.duration.months(1));
    });
    it('createPoll castVote getWeight checkIfVoted endPoll', async () => {
      await voting1.createPoll('Solana Integration', new BN(30), {from: bob});
      await voting1.getPoll(1).then(res => {
        expect(res[0]).to.eq('Solana Integration');
        expect(res[2].sub(res[1]).toString()).to.eq(time.duration.days(7).toString());
        expect(res[3].toString()).to.eq('30');
        expect(res[4].toString()).to.eq('0');
        expect(res[5]).to.eq(bob);
      });
      await voting1.getWeight.call(1, alice).then(res => {
        expect(res.toString()).to.eq('14400000000000000000000');
      });
      expect(await voting1.checkIfVoted(1, alice)).to.eq(false);
      expectEvent(
        await voting1.castVote(1, true, {from: alice}),
        'VoteCasted'
      );
      expect(await voting1.checkIfVoted(1, alice)).to.eq(true);
      await voting1.castVote(1, false, {from: bob});
      await voting1.getPollForOperator(1, {from: bob}).then(res => {
        expect(res[8].toString()).to.eq('14400000000000000000000');
        expect(res[9].toString()).to.eq('25200000000000000000000');
      });
      await timeTraveler.advanceTime(time.duration.days(7));
      expectEvent(
        await voting1.endPoll(1, {from: bob}),
        'PollStatusUpdated',
        {
          pollID: new BN(1),
          status: new BN(2)
        }
      );

      await voting1.createPoll('Tezos Integration', new BN(30), {from: bob});
      await voting1.setPollMinimumVotes(weiAmount(300000), {from: bob});
      await voting1.castVote(2, true, {from: alice});
      await voting1.castVote(2, false, {from: bob});
      await expectRevert(
        voting1.endPoll(2, {from: bob}),
        'Voting1#endPoll: POLL_PERIOD_NOT_EXPIRED'
      );
      await timeTraveler.advanceTime(time.duration.days(14));
      expectEvent(
        await voting1.endPoll(2, {from: bob}),
        'PollStatusUpdated',
        {
          pollID: new BN(2),
          status: new BN(2)
        }
      );
    });
    describe('reverts if', async () => {
      it('createPoll', async () => {
        await expectRevert(
          voting1.createPoll('Solana Integration', new BN(30), {from: carol}),
          'Voting1#onlyOperator: CALLER_NO_OPERATOR_ROLE'
        );
        await expectRevert(
          voting1.createPoll('', new BN(30), {from: bob}),
          'Voting1#createPoll: DESCRIPTION_INVALID'
        );
        await voting1.createPoll('Solana Integration', new BN(30), {from: bob});
        await expectRevert(
          voting1.getPoll(2),
          'Voting1#validPoll: POLL_ID_INVALID'
        );
        await expectRevert(
          voting1.getWeight(1, constants.ZERO_ADDRESS),
          'Voting1#getWeight: ACCOUNT_INVALID'
        );
        await expectRevert(
          voting1.endPoll(1),
          'Voting1#endPoll: POLL_PERIOD_NOT_EXPIRED'
        );
        await voting1.castVote(1, true, {from: alice});
        await expectRevert(
          voting1.castVote(1, true, {from: alice}),
          'Voting1#castVote: USER_ALREADY_VOTED'
        );
        await timeTraveler.advanceTime(time.duration.days(7));
        await voting1.endPoll(1, {from: bob});
        await expectRevert(
          voting1.castVote(1, true, {from: alice}),
          'Voting1#castVote: POLL_ALREADY_ENDED'
        );
      });
    });
  });
});
