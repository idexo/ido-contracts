const { deployMockContract } = require('@ethereum-waffle/mock-contract');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const { duration } = require('./helpers/time');

const IWIDO = require('../artifacts/contracts/interfaces/IWIDO.sol/IWIDO.json');

const ONE_TIME_TICKET_HASH = ethers.utils.id('One time access');
const ONE_MONTH_TICKET_HASH = ethers.utils.id('One month access');
const THREE_MONTH_TICKET_HASH = ethers.utils.id('Three month access');
const SIX_MONTH_TICKET_HASH = ethers.utils.id('Six month access');
const TWELVE_TICKET_HASH = ethers.utils.id('Twelve month access');
const UNLIMITED_TICKET_HASH = ethers.utils.id('Unlimited access');

async function setup() {
  const [owner, alice, bob, carol] = await ethers.getSigners();
  const wido = await deployMockContract(owner, IWIDO.abi);
  const usdt = await deployMockContract(owner, IWIDO.abi);
  const PriceStabilityPool = await ethers.getContractFactory('PriceStabilityPool');
  const contract = await PriceStabilityPool.deploy(
    'Price Stability Pool',
    'PSP',
    wido.address,
    usdt.address,
    Math.floor(Date.now() / 1000 + duration.days(3)), // when the pool stability period start
    duration.months(1), // the pool stability period
    ethers.utils.parseEther('0.0002'), // coupon gas price
    ethers.utils.parseEther('2'), // coupon stable coin price
    1000 // entrance fee in BP
  );
  return {wido, usdt, contract, owner, alice, bob, carol};
}

describe('PriceStabilityPool', async () => {
  let wido, usdt, contract;
  let owner, alice, bob, carol;

  describe('createCoupon()', async () => {
    it('expect to create coupon', async () => {
      ({wido, usdt, contract, owner, alice, bob, carol} = await setup());
      // whitelist
      await contract.addWhitelist([alice.address, bob.address]);

      await contract.connect(alice).createCoupon(5, {value: ethers.utils.parseEther('0.001')});
      await contract.connect(bob).createCoupon(15, {value: ethers.utils.parseEther('0.003')});

      // check state variable update
      expect(await contract.ownerOf(1)).to.eq(alice.address);
      await contract.couponBalances(alice.address).then(res => {
        expect(res.toString()).to.eq('5');
      });
      await contract.totalCoupon().then(res => {
        expect(res.toString()).to.eq('20');
      });
    });
    describe('reverts if', async () => {
      it('non whitelisted wallet call', async () => {
        await expect(contract.connect(carol).createCoupon(5))
          .to.be.revertedWith('Whitelist: CALLER_NO_WHITELIST');
      });
      it('zero coupon amount', async () => {
        await expect(contract.connect(alice).createCoupon(0, {value: ethers.utils.parseEther('0.0001')}))
          .to.be.revertedWith('PriceStabilityPool: COUPON_AMOUNT_INVALID');
      });
      it('insufficient Eth', async () => {
        await expect(contract.connect(alice).createCoupon(5, {value: ethers.utils.parseEther('0.00000000000001')}))
          .to.be.revertedWith('PriceStabilityPool: INSUFFICIENT_FUNDS');
      });
    });
  });

  describe('Access Ticket price', async () => {
    it('setAllTicketPrices()', async () => {
      await contract.setAllTicketPrices(
        ethers.utils.parseEther('0.5'), // reset later
        ethers.utils.parseEther('2'),
        ethers.utils.parseEther('3'),
        ethers.utils.parseEther('4'),
        ethers.utils.parseEther('5'),
        ethers.utils.parseEther('6'),
      );
      await contract.ticketPrices(ONE_TIME_TICKET_HASH).then(res => {
        expect(res.toString()).to.eq('500000000000000000');
      });
    });
    it('setTicketPrice()', async () => {
      await expect(contract.setTicketPrice(ONE_TIME_TICKET_HASH, ethers.utils.parseEther('1')))
        .to.emit(contract, 'TicketPriceSet')
        .withArgs(ONE_TIME_TICKET_HASH, ethers.utils.parseEther('1'));
    });
    it('purchaseTicket()', async () => {
      // mocks
      await wido.mock.transferFrom.withArgs(alice.address, contract.address, ethers.utils.parseEther('2.2')).returns(true);

      await contract.connect(alice).purchaseTicket(ONE_MONTH_TICKET_HASH);

      // check state variable update
      await contract.premiums(alice.address).then(res => {
        expect(res.toString()).to.eq('50000000000000000');
      });
      await contract.premiums(bob.address).then(res => {
        expect(res.toString()).to.eq('150000000000000000');
      });
      await contract.tickets(alice.address).then(res => {
        expect(res['duration'].toString()).to.eq('2678400'); // 1 month
      });
    });
    describe('reverts if', async () => {
      it('setAllTicketPrices() - non owner call', async () => {
        await expect(contract.connect(alice).setAllTicketPrices(
          ethers.utils.parseEther('1'),
          ethers.utils.parseEther('2'),
          ethers.utils.parseEther('3'),
          ethers.utils.parseEther('4'),
          ethers.utils.parseEther('5'),
          ethers.utils.parseEther('6'),
        )).to.be.revertedWith('Ownable: CALLER_NO_OWNER');
      });
      it('setTicketPrice() - non owner call', async () => {
        await expect(contract.connect(alice).setTicketPrice(ONE_TIME_TICKET_HASH, ethers.utils.parseEther('1')))
          .to.be.revertedWith('Ownable: CALLER_NO_OWNER');
      });
    });
  });
});
