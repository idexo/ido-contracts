const MultipleVoting = artifacts.require('contracts/voting/MultipleVoting.sol:MultipleVoting');
const StakePool = artifacts.require('StakePool');
const ERC20 = artifacts.require('ERC20Mock');

const { expect } = require('chai');
const {
  BN,
  constants,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');
const { toWei } = require('web3-utils');
const time = require('./helpers/time');
const timeTraveler = require('ganache-time-traveler');

contract('MultipleVoting', async accounts => {
  let ido, erc20;
  let voting, sPool1, sPool2, sPool3;
  const [alice, bob, carol] = accounts;

  before(async () => {
    ido = await ERC20.new('Idexo Community', 'IDO');
    erc20 = await ERC20.new('USD Tether', 'USDT');
    sPool1 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
    sPool2 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
    sPool3 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
    voting = await MultipleVoting.new([sPool1.address, sPool2.address]);
  });

  describe('#Role', async () => {
    it ('should add operator', async () => {
      await voting.addOperator(bob);
      expect(await voting.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await voting.removeOperator(bob);
      expect(await voting.checkOperator(bob)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('add operator by non-admin', async () => {
        await expectRevert(
          voting.addOperator(bob, {from: bob}),
          'MultipleVoting#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
      it('remove operator by non-admin', async () => {
        await voting.addOperator(bob);
        await expectRevert(
          voting.removeOperator(bob, {from: bob}),
          'MultipleVoting#onlyAdmin: CALLER_NO_ADMIN_ROLE'
        );
      });
    });
  });

  describe('#StakePool', async () => {
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
      await voting.removeStakePool(sPool3.address, {from: bob});
      await voting.getStakePools().then(res => {
        expect(res.length).to.eq(2);
        expect(res[0]).to.eq(sPool1.address);
        expect(res[1]).to.eq(sPool2.address);
      });
    });
    describe('reverts if', async () => {
      it('addStakePool removeStakePool', async () => {
        await expectRevert(
          voting.addStakePool(sPool3.address, {from: carol}),
          'MultipleVoting#onlyOperator: CALLER_NO_OPERATOR_ROLE'
        );
        await expectRevert(
          voting.addStakePool(constants.ZERO_ADDRESS, {from: bob}),
          'MultipleVoting#addStakePool: STAKE_POOL_ADDRESS_INVALID'
        );
        await expectRevert(
          voting.addStakePool(sPool2.address, {from: bob}),
          'MultipleVoting#addStakePool: STAKE_POOL_ADDRESS_ALREADY_FOUND'
        );
      });
    });
  });

  describe('#Poll', async () => {
    before(async () => {
      await ido.mint(alice, toWei(new BN(10000000)));
      await ido.mint(bob, toWei(new BN(10000000)));
      await ido.approve(sPool1.address, toWei(new BN(10000000)));
      await ido.approve(sPool2.address, toWei(new BN(10000000)));
      await ido.approve(sPool1.address, toWei(new BN(10000000)), {from: bob});
      await ido.approve(sPool2.address, toWei(new BN(10000000)), {from: bob});
      await sPool1.deposit(toWei(new BN(4000)));
      await sPool1.deposit(toWei(new BN(7000)), {from: bob});
      await sPool2.deposit(toWei(new BN(8000)));
      await sPool2.deposit(toWei(new BN(14000)), {from: bob});
      await timeTraveler.advanceTime(time.duration.months(1));
    });
    it('createPoll castVote getWeight checkIfVoted endPoll', async () => {
      // create and start poll
      await voting.createPoll('Which network is next target?', ['Solana', 'Tezos', 'Cardano'], new BN(3), new BN(30), {from: bob});
      await voting.getPollInfo(1).then(res => {
        expect(res[0]).to.eq('Which network is next target?');
        expect(res[1].length).to.eq(4);
        expect(res[3].sub(res[2]).toString()).to.eq(time.duration.days(3).toString());
        expect(res[4].toString()).to.eq('30');
        expect(res[5]).to.eq(false);
        expect(res[6]).to.eq(bob);
      });
      await voting.getWeight.call(1, alice).then(res => {
        expect(res.toString()).to.eq('12000000000000000000000');
      });
      expect(await voting.checkIfVoted(1, alice)).to.eq(false);
      expectEvent(
        await voting.castVote(1, 1, {from: alice}),
        'VoteCasted'
      );
      expect(await voting.checkIfVoted(1, alice)).to.eq(true);
      await voting.castVote(1, 2, {from: bob});
      // poll is still on, operators can call
      await voting.getPollVotingInfo(1, {from: bob}).then(res => {
        expect(res[0][0].toString()).to.eq('0');
        expect(res[0][1].toString()).to.eq('12000000000000000000000');
        expect(res[0][2].toString()).to.eq('21000000000000000000000');
        expect(res[0][3].toString()).to.eq('0');
      });
      await voting.getVoterInfo(1, alice, {from: bob}).then(res => {
        expect(res[0].toString()).to.eq('1');
        expect(res[1].toString()).to.eq('12000000000000000000000');
      });
      await timeTraveler.advanceTime(time.duration.days(3));
      // end poll
      expectEvent(
        await voting.endPoll(1, {from: bob}),
        'PollEnded',
        {
          pollID: new BN(1),
          winningOptionID: new BN(2)
        }
      );
      // poll is ended, anybody can call
      await voting.getPollVotingInfo(1, {from: carol}).then(res => {
        expect(res[0][0].toString()).to.eq('0');
        expect(res[0][1].toString()).to.eq('12000000000000000000000');
        expect(res[0][2].toString()).to.eq('21000000000000000000000');
        expect(res[0][3].toString()).to.eq('0');
      });
      await voting.getVoterInfo(1, alice, {from: carol}).then(res => {
        expect(res[0].toString()).to.eq('1');
        expect(res[1].toString()).to.eq('12000000000000000000000');
      });
    });
    describe('reverts if', async () => {
      it('createPoll, castVote, endPoll, getWeight, getters: getPollInfo, getPollVotingInfo, getVoterInfo', async () => {
        await expectRevert(
          voting.createPoll('Which feature do you love most about Idexo?', ['Staking', 'Voting', 'CommunityNFT'], new BN(3), new BN(30), {from: carol}),
          'MultipleVoting#onlyOperator: CALLER_NO_OPERATOR_ROLE'
        );
        await expectRevert(
          voting.createPoll('', ['Staking', 'Voting', 'CommunityNFT'], new BN(3), new BN(30), {from: bob}),
          'MultipleVoting#createPoll: DESCRIPTION_INVALID'
        );
        await expectRevert(
          voting.createPoll('Which feature do you love most about Idexo?', ['Staking', 'Voting', 'CommunityNFT'], new BN(0), new BN(30), {from: bob}),
          'MultipleVoting#createPoll: DURATION_TIME_INVALID'
        );
        await voting.createPoll('Which feature do you love most about Idexo?', ['Staking', 'Voting', 'CommunityNFT'], new BN(3), new BN(30), {from: bob});
        await expectRevert(
          voting.getWeight(2, constants.ZERO_ADDRESS),
          'MultipleVoting#getWeight: ACCOUNT_INVALID'
        );
        await expectRevert(
          voting.endPoll(2),
          'MultipleVoting#endPoll: VOTING_PERIOD_NOT_EXPIRED'
        );
        await voting.castVote(2, 1, {from: alice});
        await expectRevert(
          voting.castVote(2, 1, {from: alice}),
          'MultipleVoting#castVote: USER_ALREADY_VOTED'
        );
        await expectRevert(
          voting.getPollInfo(3),
          'MultipleVoting#validPoll: POLL_ID_INVALID'
        );
        await expectRevert(
          voting.getPollVotingInfo(2, {from: carol}),
          'MultipleVoting#getPollVotingInfo: POLL_NOT_ENDED__CALLER_NO_OPERATOR'
        );
        await expectRevert(
          voting.getVoterInfo(2, alice, {from: carol}),
          'MultipleVoting#getVoterInfo: POLL_NOT_ENDED__CALLER_NO_OPERATOR'
        );
        await timeTraveler.advanceTime(time.duration.days(3));
        await voting.endPoll(2, {from: bob});
        await expectRevert(
          voting.castVote(2, 1, {from: alice}),
          'MultipleVoting#castVote: POLL_ALREADY_ENDED'
        );
      });
    });
  });
});
