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
    duration.months(1),
    Math.floor(Date.now() / 1000 + 2),
    ethers.utils.parseEther('0.0002'),
    ethers.utils.parseEther('2'),
    1000
  );
  return {wido, usdt, contract, owner, alice, bob, carol};
}

describe('PriceStabilityPool', async () => {
  let wido, usdt, contract;
  let owner, alice, bob, carol;

  describe('Access Ticket', async () => {
    it('setAllTicketPrices()', async () => {
      ({wido, usdt, contract, owner, alice, bob, carol} = await setup());
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
    describe('reverts if', async () => {
      it('non owner call setAllTicketPrices()', async () => {
        await expect(contract.connect(alice).setAllTicketPrices(
          ethers.utils.parseEther('1'),
          ethers.utils.parseEther('2'),
          ethers.utils.parseEther('3'),
          ethers.utils.parseEther('4'),
          ethers.utils.parseEther('5'),
          ethers.utils.parseEther('6'),
        )).to.be.revertedWith('Ownable: CALLER_NO_OWNER');
      });
    });
  });
});
