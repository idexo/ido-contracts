const MultipleVotingMirror = artifacts.require('MultipleVotingMirror');
const StakeMirrorNFT = artifacts.require('contracts/staking/StakeMirrorNFT.sol:StakeMirrorNFT');
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

contract('MultipleVotingMirror', async accounts => {
  let voting, sPool1, sPool2, sPool3;
  const [alice, bob, carol] = accounts;

  before(async () => {
    // ido = await ERC20.new('Idexo Community', 'IDO');
    // erc20 = await ERC20.new('USD Tether', 'USDT');
    sPool1 = await StakeMirrorNFT.new('IGSP Mirror', 'IGSPM', 'https://idexo.io/metadata/');
    sPool2 = await StakeMirrorNFT.new('IGSP Mirror', 'IGSPM', 'https://idexo.io/metadata/');
    sPool3 = await StakeMirrorNFT.new('IGSP Mirror', 'IGSPM', 'https://idexo.io/metadata/');
    // sPool2 = await StakeMirrorNFT.new('Idexo Stake Token', 'IDS', 'https://idexo.io/metadata/');
    // sPool3 = await StakeMirrorNFT.new('Idexo Stake Token', 'IDS', 'https://idexo.io/metadata/');
    voting = await MultipleVotingMirror.new([sPool1.address, sPool2.address]);
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
          'CALLER_NO_ADMIN_ROLE'
        );
      });
      it('remove operator by non-admin', async () => {
        await voting.addOperator(bob);
        await expectRevert(
          voting.removeOperator(bob, {from: bob}),
          'CALLER_NO_ADMIN_ROLE'
        );
      });
    });
  });

  describe('#StakeMirrorNFT', async () => {
    it('addStakePool', async () => {
      await voting.addStakePool(sPool3.address, {from: bob});
      expect(await voting.isStakePool(sPool1.address)).to.eq(true);
      expect(await voting.isStakePool(sPool2.address)).to.eq(true);
      expect(await voting.isStakePool(sPool3.address)).to.eq(true);
    });
    it('supportsInterface', async () => {
      await sPool1.supportsInterface("0x00").then(res => {
        expect(res).to.eq(false);
      });
    });
    it('addOperator removeOperator', async () => {
      await sPool1.addOperator(bob);
      expect(await sPool1.checkOperator(bob)).to.eq(true);
      await sPool1.removeOperator(bob);
      expect(await sPool1.checkOperator(bob)).to.eq(false);
    });
    it('getStakeAmount isHolder setTokenURI tokenURI decreaseStakeAmount', async () => {
      await sPool1.getStakeAmount(bob).then(res => { expect(res.words[0]).to.eq(0) });
      await sPool1.mint(bob, 1, toWei(new BN(4000)), 120, 1632842216);
      expect(await sPool1.isHolder(bob)).to.eq(true);
      await sPool1.setTokenURI(1, "test");
      expect(await sPool1.tokenURI(1)).to.eq("https://idexo.io/metadata/test");
      await sPool1.decreaseStakeAmount(1, toWei(new BN(4000)));
      await sPool1.getStakeAmount(bob).then(res => { expect(res.words[0]).to.eq(0) });
    });
    it('removeStakePool', async () => {
      await voting.removeStakePool(sPool3.address, {from: bob});
      expect(await voting.isStakePool(sPool3.address)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('addStakePool removeStakePool', async () => {
        await expectRevert(
          voting.addStakePool(sPool3.address, {from: carol}),
          'CALLER_NO_OPERATOR_ROLE'
        );
        await expectRevert(
          voting.addStakePool(constants.ZERO_ADDRESS, {from: bob}),
          'STAKE_POOL_ADDRESS_INVALID'
        );
        await expectRevert(
          voting.addStakePool(sPool2.address, {from: bob}),
          'STAKE_POOL_ADDRESS_ALREADY_FOUND'
        );
      });
    });
  });

  describe('#Poll', async () => {
    before(async () => {
      await sPool1.mint(alice, 1, toWei(new BN(4000)), 120, 1632842216);
      await sPool1.mint(bob, 2, toWei(new BN(7000)), 120, 1632842216);
      await sPool2.mint(alice, 1, toWei(new BN(8000)), 120, 1632842216);
      await sPool2.mint(bob, 2, toWei(new BN(14000)), 120, 1632842216);
    });
    it('createPoll castVote getWeight checkIfVoted endPoll', async () => {
      // create and start poll
      const startTime = Math.floor(Date.now() / 1000) + time.duration.days(100);
      const endTime = startTime + time.duration.days(10);
      const newEndTime = endTime + time.duration.days(5);
      // non-operator can not create the poll
      await expectRevert(
        voting.createPoll('Which network is next target?', ['Solana', 'Tezos', 'Cardano'], startTime, endTime, 0, {from: carol}),
        'CALLER_NO_OPERATOR_ROLE'
      );
      // poll description must not be empty
      await expectRevert(
        voting.createPoll('', ['Solana', 'Tezos', 'Cardano'], startTime, endTime, 0, {from: bob}),
        'DESCRIPTION_INVALID'
      );
      // startTime and endTime must not be same
      await expectRevert(
        voting.createPoll('Which network is next target?', ['Solana', 'Tezos', 'Cardano'], startTime, startTime, 0, {from: bob}),
        'END_TIME_INVALID'
      );
      // operator can create
      await voting.createPoll('Which network is next target?', ['Solana', 'Tezos', 'Cardano'], startTime, endTime, 0, {from: bob});
      // returns general poll info, anybody can call anytime
      await voting.getPollInfo(1).then(res => {
        expect(res[0]).to.eq('Which network is next target?');
        expect(res[1].length).to.eq(4);
        expect(res[3].sub(res[2]).toString()).to.eq(time.duration.days(10).toString());
        expect(res[4].toString()).to.eq('0');
        expect(res[5]).to.eq(bob);
      });
      expect(await voting.checkIfVoted(1, alice)).to.eq(false);
      expectEvent(
        await voting.castVote(1, 1, {from: alice}),
        'VoteCasted'
      );
      expect(await voting.checkIfVoted(1, alice)).to.eq(true);
      await voting.castVote(1, 2, {from: bob});
      // zero weight stakers can not cast vote
      await expectRevert(
        voting.castVote(1, 1, {from: carol}),
        'NO_VALID_VOTING_NFTS_PRESENT'
      );
      await voting.updatePollTime(1, 0, newEndTime, {from: bob});
      // poll is still on
      // operators only can call
      await voting.getPollVotingInfo(1, {from: bob}).then(res => {
        expect(res[0][0].toString()).to.eq('0');
        expect(res[0][1].toString()).to.eq('12000000000000000000000');
        expect(res[0][2].toString()).to.eq('21000000000000000000000');
        expect(res[0][3].toString()).to.eq('0');
        expect(res[1].toString()).to.eq('2');
      });
      // non-operator can not call
      await expectRevert(
        voting.getPollVotingInfo(1, {from: carol}),
        'POLL_NOT_ENDED__CALLER_NO_OPERATOR'
      );
      // operators only can call
      await voting.getVoterInfo(1, alice, {from: bob}).then(res => {
        expect(res[0].toString()).to.eq('1');
        expect(res[1].toString()).to.eq('12000000000000000000000');
      });
      // non-operator can not call
      await expectRevert(
        voting.getVoterInfo(1, alice, {from: carol}),
        'POLL_NOT_ENDED__CALLER_NO_OPERATOR'
      );
      await timeTraveler.advanceTimeAndBlock(time.duration.days(200));
      // poll ended, anybody can call
      await voting.getPollVotingInfo(1, {from: carol}).then(res => {
        expect(res[0][0].toString()).to.eq('0');
        expect(res[0][1].toString()).to.eq('12000000000000000000000');
        expect(res[0][2].toString()).to.eq('21000000000000000000000');
        expect(res[0][3].toString()).to.eq('0');
        expect(res[1].toString()).to.eq('2');
      });
      await voting.getVoterInfo(1, alice, {from: carol}).then(res => {
        expect(res[0].toString()).to.eq('1');
        expect(res[1].toString()).to.eq('12000000000000000000000');
      });
      await timeTraveler.advanceTimeAndBlock(time.duration.days(-200));
    });
  });
});