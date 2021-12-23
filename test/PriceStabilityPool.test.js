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
    Math.floor(Date.now() / 1000 + duration.days(3)), // the pool stability period starts after 3 days
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
      expect(await contract.couponBalances(alice.address)).to.eq(5);
      expect(await contract.totalCoupon()).to.eq(20);
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

  describe('Access Ticket', async () => {
    it('setAllTicketPrices()', async () => {
      await contract.setAllTicketPrices(
        ethers.utils.parseEther('0.5'), // reset later
        ethers.utils.parseEther('2'),
        ethers.utils.parseEther('3'),
        ethers.utils.parseEther('4'),
        ethers.utils.parseEther('5'),
        ethers.utils.parseEther('6'),
      );
      expect(await contract.ticketPrices(ONE_TIME_TICKET_HASH)).to.eq(ethers.utils.parseEther('0.5'));
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
      expect(await contract.premiums(alice.address)).to.eq(ethers.utils.parseEther('0.05'));
      expect(await contract.premiums(bob.address)).to.eq(ethers.utils.parseEther('0.15'));
      await contract.tickets(alice.address).then(res => {
        expect(res['duration']).to.eq(2678400); // 1 month
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

  describe('purchaseCoupon()', async () => {
    it('expect to purchase coupon', async () => {
      // mocks
      await usdt.mock.transferFrom.withArgs(alice.address, alice.address, ethers.utils.parseEther('10')).returns(true);
      await usdt.mock.transferFrom.withArgs(alice.address, bob.address, ethers.utils.parseEther('4')).returns(true);

      await contract.connect(alice).purchaseCoupon(7);

      // check state variable update
      await expect(contract.ownerOf(1))
        .to.be.revertedWith('ERC721: owner query for nonexistent token');
      expect(await contract.stakedCoupons(1)).to.eq(0);
      expect(await contract.stakedCoupons(2)).to.eq(13);
      expect(await contract.couponBalances(alice.address)).to.eq(0);
      expect(await contract.couponBalances(bob.address)).to.eq(13);
      expect(await contract.totalCoupon()).to.eq(13);
      expect(await contract.firstStakeId()).to.eq(2);
    });
    describe('reverts if', async () => {
      it('purchase amount is zero', async () => {
        await expect(contract.connect(alice).purchaseCoupon(0))
          .to.be.revertedWith('PriceStabilityPool: COUPON_AMOUNT_INVALID');
      });
      it('purchase amount is greater than total coupon amount', async () => {
        await expect(contract.connect(alice).purchaseCoupon(21))
          .to.be.revertedWith('PriceStabilityPool: COUPON_AMOUNT_INVALID');
      });
      it('caller has no valid access tickets', async () => {
        await expect(contract.connect(carol).purchaseCoupon(7))
          .to.be.revertedWith('PriceStabilityPool: ACCESS_TICKET_INVALID');
      });
    });
  });

  describe('useCoupon()', async () => {
    it('expect to use coupon', async () => {
      // 3 days passed
      await network.provider.send("evm_increaseTime", [duration.days(3)]);
      await network.provider.send("evm_mine");

      await contract.connect(alice).useCoupon(5);

      // check state variable update
      expect(await contract.purchasedCoupons(alice.address)).to.eq(2);
    });
    describe('reverts if', async () => {
      it('coupon amount is zero', async () => {
        await expect(contract.connect(alice).useCoupon(0))
          .to.be.revertedWith('PriceStabilityPool: COUPON_AMOUNT_INVALID');
      });
      it('coupon amount is greater than purchased amount', async () => {
        await expect(contract.connect(alice).useCoupon(3))
          .to.be.revertedWith('PriceStabilityPool: COUPON_AMOUNT_INVALID');
      });
    });
  });

  describe('claim()', async () => {
    it('expect to claim premuim', async () => {
      // mocks
      await wido.mock.transfer.withArgs(alice.address, ethers.utils.parseEther('0.04')).returns(true);

      await contract.connect(alice).claim(ethers.utils.parseEther('0.04'));

      // check state variable update
      expect(await contract.premiums(alice.address)).to.eq(ethers.utils.parseEther('0.01'));
    });
    describe('reverts if', async () => {
      it('claim amount is zero', async () => {
        await expect(contract.connect(alice).claim(0))
          .to.be.revertedWith('PriceStabilityPool: CLAIM_AMOUNT_INVALID');
      });
      it('claim amount is greater than available amount', async () => {
        await expect(contract.connect(alice).claim(ethers.utils.parseEther('0.02')))
          .to.be.revertedWith('PriceStabilityPool: CLAIM_AMOUNT_INVALID');
      });
    });
  });
});
