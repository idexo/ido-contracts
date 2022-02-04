const { expect } = require('chai');
const {
  BN,
  constants,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');
const timeTraveler = require('ganache-time-traveler');
const {
  duration,
  increase
} = require('./helpers/time');

const IDOSale = artifacts.require('IDOSale');
const ERC20Mock = artifacts.require('ERC20Mock');

const toUSDTWei = (amount) => new BN(amount).mul(new BN(10).pow(new BN(6)));
const dummyHash = '0xf408509b00caba5d37325ab33a92f6185c9b5f007a965dfbeff7b81ab1ec871b';

contract('IDOSale', async accounts => {
  let saleContract;
  let ido, usdt;
  const [alice, bob, carol, darren] = accounts;
  let startTime, endTime;

  before(async () => {
    ido = await ERC20Mock.new('Idexo token', 'IDO');
    ido.mint(alice, web3.utils.toWei(new BN(10000)));
    // USDT decimals is 6
    usdt = await ERC20Mock.new('USDT token', 'USDT');
    usdt.mint(alice, toUSDTWei(10000));
    usdt.mint(bob, toUSDTWei(10000));
    usdt.mint(carol, toUSDTWei(10000));

    const currentTime = Math.floor(Date.now() / 1000);
    startTime = currentTime + duration.days(1);
    endTime = startTime + duration.days(7);

    saleContract = await IDOSale.new(ido.address, usdt.address, new BN(450000), web3.utils.toWei(new BN(11111)), startTime, endTime);
    await saleContract.addOperator(alice);
  });

  describe('#Role', async () => {
    it ('should add operator', async () => {
      await saleContract.addOperator(bob);
      expect(await saleContract.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await saleContract.removeOperator(bob);
      expect(await saleContract.checkOperator(bob)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('add operator by non-operator', async () => {
        await expectRevert(
          saleContract.addOperator(bob, {from: bob}),
          'IDOSale: CALLER_NO_OWNER'
        );
      });
      it('remove operator by non-operator', async () => {
        await saleContract.addOperator(bob);
        await expectRevert(
          saleContract.removeOperator(bob, {from: bob}),
          'IDOSale: CALLER_NO_OWNER'
        );
      });
    });
  });

  describe('#Whitelist', async () => {
    it('addWhitelist, removeWhitelist', async () => {
      await saleContract.addWhitelist([alice, bob, carol, darren], {from: bob});
      expect(await saleContract.whitelist(alice)).to.eq(true);
      expect(await saleContract.whitelist(darren)).to.eq(true);
      await saleContract.removeWhitelist([darren]);
      expect(await saleContract.whitelist(alice)).to.eq(true);
      expect(await saleContract.whitelist(darren)).to.eq(false);
      await saleContract.whitelistedUsers().then(res => {
        expect(res.length).to.eq(4);
        expect(res[0]).to.eq(alice);
        expect(res[3]).to.eq(constants.ZERO_ADDRESS);
      });
    });
    describe('reverts if', async () => {
      it('non-operator call addWhitelist/removeWhitelist', async () => {
        await expectRevert(
          saleContract.addWhitelist([alice, bob], {from: carol}),
          'IDOSale: CALLER_NO_OPERATOR_ROLE'
        );
        await expectRevert(
          saleContract.removeWhitelist([alice, bob], {from: carol}),
          'IDOSale: CALLER_NO_OPERATOR_ROLE'
        );
      });
      it('zero address', async () => {
        await expectRevert(
          saleContract.addWhitelist([constants.ZERO_ADDRESS], {from: bob}),
          'IDOSale: ZERO_ADDRESS'
        );
        await expectRevert(
          saleContract.removeWhitelist([constants.ZERO_ADDRESS], {from: bob}),
          'IDOSale: ZERO_ADDRESS'
        );
      });
    });
  });

  describe('#Token Management 1', async () => {
    describe('reverts if (before sale start)', async () => {
      it('non-operator call depositTokens', async () => {
        await expectRevert(
          saleContract.depositTokens(web3.utils.toWei(new BN(10000)), {from: carol}),
          'IDOSale: CALLER_NO_OPERATOR_ROLE'
        );
      });
      it('zero amount in depositTokens', async () => {
        await expectRevert(
          saleContract.depositTokens(web3.utils.toWei(new BN(0)), {from: bob}),
          'IDOSale: DEPOSIT_AMOUNT_INVALID'
        );
      });
      it('call purchase when sale is not started', async () => {
        await expectRevert(
          saleContract.purchase(web3.utils.toWei(new BN(20)), {from: bob}),
          'IDOSale: SALE_NOT_STARTED'
        );
      });
    });
  });

  describe('#Token Management 2', async () => {
    before(async () => {
      // 2 days passed
      timeTraveler.advanceTime(duration.days(2));
    });
    describe('depositTokens, purchase', async () => {
      it('depositTokens, purchase', async () => {
        await ido.approve(saleContract.address, web3.utils.toWei(new BN(10000)), {from: alice});
        expectEvent(
          await saleContract.depositTokens(web3.utils.toWei(new BN(200)), {from: alice}),
          'Deposited'
        );
        await usdt.approve(saleContract.address, toUSDTWei(new BN(10000)), {from: bob});
        /*await usdt.balanceOf(bob).then(res => {
          console.log(res.toString());
        });*/
        expectEvent(
          await saleContract.purchase(web3.utils.toWei(new BN(20)), {from: bob}),
          'Purchased'
        );
        // Check USDT balance of sale contract
        await usdt.balanceOf(saleContract.address).then(res => {
          expect(res.toString()).to.eq('9000000');
        })
        await usdt.balanceOf(bob).then(res => {
          expect(res.toString()).to.eq('9991000000');
        })
        await usdt.approve(saleContract.address, toUSDTWei(new BN(10000)), {from: carol});
        await saleContract.purchase(web3.utils.toWei(new BN(30)), {from: carol})
        // Check usdt balance of sale contract
        await usdt.balanceOf(saleContract.address).then(res => {
          expect(res.toString()).to.eq('22500000');
        })
        await saleContract.purchaseHistory().then(res => {
          expect(res.length).to.eq(4);
        });
      });
      it('permit and deposit', async () => {
        await expectRevert(
          saleContract.permitAndDepositTokens(new BN(0), { nonce: 0, deadline: 0, v: 0, r: dummyHash, s: dummyHash }),
          'IDOSale: DEPOSIT_AMOUNT_INVALID'
        );
      });
    });
    describe('reverts if (after sale start)', async () => {
      it('zero amount in purchase', async () => {
        await expectRevert(
          saleContract.purchase(web3.utils.toWei(new BN(0)), {from: bob}),
          'IDOSale: PURCHASE_AMOUNT_INVALID'
        );
      });
      it('non-whitelisted user call purchase', async () => {
        await expectRevert(
          saleContract.purchase(web3.utils.toWei(new BN(20)), {from: darren}),
          'IDOSale: CALLER_NO_WHITELIST'
        );
      });
      it('purchase when deposit cap exceeded', async () => {
        await expectRevert(
          saleContract.purchase(web3.utils.toWei(new BN(11111)), {from: bob}),
          'IDOSale: PURCHASE_CAP_EXCEEDED'
        );
      });
      it('purchase when sellable balance exceeded', async () => {
        await expectRevert(
          saleContract.purchase(web3.utils.toWei(new BN(200)), {from: bob}),
          'IDOSale: INSUFFICIENT_SELL_BALANCE'
        );
      });
      it('claim when the sale not ended', async () => {
        await expectRevert(
          saleContract.claim(web3.utils.toWei(new BN(20)), {from: bob}),
          'IDOSale: SALE_NOT_ENDED'
        );
      });
      it('sweep when the sale not ended', async () => {
        await expectRevert(
          saleContract.sweep(darren),
          'IDOSale: SALE_NOT_ENDED'
        );
      });
      it('permit and purchase 0 amount', async () => {
        await expectRevert(
          saleContract.permitAndPurchase(new BN(0), { nonce: 0, deadline: 0, v: 0, r: dummyHash, s: dummyHash }),
          'IDOSale: PURCHASE_AMOUNT_INVALID'
        );
      });
      it('permit and purchase no whitelist', async () => {
        await expectRevert(
          saleContract.permitAndPurchase(new BN(10), { nonce: 0, deadline: 0, v: 0, r: dummyHash, s: dummyHash }, {from: darren}),
          'IDOSale: CALLER_NO_WHITELIST'
        );
      });
      it('permit and purchase over cap', async () => {
        await saleContract.setPurchaseCap(web3.utils.toWei(new BN(0)))
        await expectRevert(
          saleContract.permitAndPurchase(new BN(1000000), { nonce: 0, deadline: 0, v: 0, r: dummyHash, s: dummyHash }, {from: bob}),
          'IDOSale: PURCHASE_CAP_EXCEEDED'
        );
      });
    });
    describe('claim, sweep', async () => {
      it('claim', async () => {
        // 7 days passed
        timeTraveler.advanceTime(duration.days(7));
        expectEvent(
          await saleContract.claim(web3.utils.toWei(new BN(10)), {from: bob}),
          'Claimed'
        );
        await ido.balanceOf(bob).then(res => {
          expect(res.toString()).to.eq('10000000000000000000');
        });
      });
      it('sweep', async () => {
        expectEvent(
          await saleContract.sweep(darren),
          'Swept'
        );
        await usdt.balanceOf(darren).then(res => {
          expect(res.toString()).to.eq('22500000');
        });
      });
    });
    describe('reverts if (after sale end)', async () => {
      it('claim with amount 0', async () => {
        await expectRevert(
          saleContract.claim(web3.utils.toWei(new BN(0)), {from: bob}),
          'IDOSale: CLAIM_AMOUNT_INVALID'
        );
      });
      it('claim amount exceeded', async () => {
        await expectRevert(
          saleContract.claim(web3.utils.toWei(new BN(15)), {from: bob}),
          'IDOSale: CLAIM_AMOUNT_EXCEEDED'
        );
      });
      it('non-owner call sweep', async () => {
        await expectRevert(
          saleContract.sweep(alice, {from: bob}),
          'IDOSale: CALLER_NO_OWNER'
        );
      });
      it('sweep to zero address', async () => {
        await expectRevert(
          saleContract.sweep(constants.ZERO_ADDRESS),
          'IDOSale: ADDRESS_INVALID'
        );
      });
      it('permit and purchase', async () => {
        await expectRevert(
          saleContract.permitAndPurchase(new BN(1), { nonce: 0, deadline: 0, v: 0, r: dummyHash, s: dummyHash }),
          'IDOSale: SALE_ALREADY_ENDED'
        );
      });
    });
  });

  describe('#Pause', async () => {
    it('should be paused/unpaused by operator', async () => {
      await saleContract.pause({from: bob});
      expect(await saleContract.paused()).to.eq(true);
      await expectRevert(
        saleContract.addWhitelist([alice, bob, carol, darren], {from: bob}),
        'Pausable: paused'
      );
      await saleContract.unpause({from: bob});
      expect(await saleContract.paused()).to.eq(false);
    });
    describe('reverts if', async () => {
      it('pause/unpause by non-operator', async () => {
        await expectRevert(
          saleContract.pause({from: carol}),
          'IDOSale: CALLER_NO_OPERATOR_ROLE'
        );
      });
    });
  });

  describe('#Setters', async () => {
    it('setIdoPrice, setPurchaseCap', async () => {
      expectEvent(
        await saleContract.setIdoPrice(new BN(550000)),
        'IdoPriceChanged'
      );
      expectEvent(
        await saleContract.setPurchaseCap(web3.utils.toWei(new BN(22222))),
        'PurchaseCapChanged'
      );
    });
    describe('reverts if', async () => {
      it('non-owner call setIdoPrice/setPurchaseCap', async () => {
        await expectRevert(
          saleContract.setIdoPrice(new BN(550000), {from: bob}),
          'IDOSale: CALLER_NO_OWNER'
        );
        await expectRevert(
          saleContract.setPurchaseCap(web3.utils.toWei(new BN(222222)), {from: bob}),
          'IDOSale: CALLER_NO_OWNER'
        );
      });
    });
  });

  describe('#Ownership', async () => {
    it('should transfer ownership', async () => {
      await saleContract.transferOwnership(bob);
      await saleContract.acceptOwnership({from: bob});
      expect(await saleContract.owner()).to.eq(bob);
    });
    describe('reverts if', async () => {
      it('non-owner call transferOwnership', async () => {
        await expectRevert(
          saleContract.transferOwnership(bob, {from: carol}),
          'IDOSale: CALLER_NO_OWNER'
        );
      });
      it('call transferOwnership with zero address', async () => {
        await expectRevert(
          saleContract.transferOwnership(constants.ZERO_ADDRESS, {from: bob}),
          'IDOSale: INVALID_ADDRESS'
        );
      });
      it('non owner call renounceOwnership', async () => {
        await expectRevert(
           saleContract.renounceOwnership({from: darren}),
          'IDOSale: CALLER_NO_OWNER'
        );
      });
      it('non new owner call acceptOwnership', async () => {
        await saleContract.transferOwnership(alice, {from: bob});
        await expectRevert(
          saleContract.acceptOwnership({from: carol}),
          'IDOSale: CALLER_NO_NEW_OWNER'
        );
        expectEvent(
          await saleContract.renounceOwnership({from: bob}),
          'OwnershipTransferred'
        )
      })
    });
  });
});
