const { expect } = require('chai');
const {
  BN,
  constants,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');

const IDOSale = artifacts.require('IDOSale');
const ERC20Mock = artifacts.require('ERC20Mock');

contract('IDOSale', async accounts => {
  let saleContract;
  let ido, usdt;
  const [alice, bob, carol, darren] = accounts;

  describe('#Role', async () => {
    it ('should add operator', async () => {
      ido = await ERC20Mock.new('Idexo token', 'IDO');
      ido.mint(alice, web3.utils.toWei(new BN(10000)));
      usdt = await ERC20Mock.new('USDT token', 'USDT');
      usdt.mint(alice, web3.utils.toWei(new BN(10000)));
      usdt.mint(bob, web3.utils.toWei(new BN(10000)));
      usdt.mint(carol, web3.utils.toWei(new BN(10000)));

      saleContract = await IDOSale.new(ido.address, usdt.address, new BN(5));

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

  describe('#Setters', async () => {
    it('setIdoPrice, setPurchaseCap', async () => {
      expectEvent(
        await saleContract.setIdoPrice(new BN(6)),
        'IdoPriceChanged'
      );
      expectEvent(
        await saleContract.setPurchaseCap(web3.utils.toWei(new BN(100))),
        'PurchaseCapChanged'
      );
    });
    describe('reverts if', async () => {
      it('non-owner call setIdoPrice/setPurchaseCap', async () => {
        await expectRevert(
          saleContract.setIdoPrice(new BN(6), {from: bob}),
          'IDOSale: CALLER_NO_OWNER'
        );
        await expectRevert(
          saleContract.setPurchaseCap(web3.utils.toWei(new BN(100)), {from: bob}),
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

  describe('#Token Management', async () => {
    it('depositTokens, purcahse', async () => {
      // await
      // await saleContract.depositTokens(web)
    });
  });
});
