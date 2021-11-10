const { expect } = require('chai');
const {
  BN,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');


const RelayManagerETHBatch = artifacts.require('RelayManagerETHBatch');
const ERC20PermitMock = artifacts.require('ERC20PermitMock');

contract('RelayManagerETHBatch', async accounts => {
  let relayManager;
  let ido;
  const [alice, bob, carol] = accounts;
  const idoName = 'Idexo Token';
  const idoSymbol = 'IDO';

  before(async () => {
    ido = await ERC20PermitMock.new(idoName, idoSymbol);
    relayManager = await RelayManagerETHBatch.new(ido.address, new BN(30));

    ido.mint(alice, web3.utils.toWei(new BN(1000)));
    ido.mint(carol, web3.utils.toWei(new BN(1000)));
    await ido.approve(relayManager.address, web3.utils.toWei(new BN(1000)), {from: alice});
  });

  describe('#Role', async () => {
    it ('should add operator', async () => {
      await relayManager.addOperator(bob);
      expect(await relayManager.checkOperator(bob)).to.eq(true);
    });
    it('should remove operator', async () => {
      await relayManager.removeOperator(bob);
      expect(await relayManager.checkOperator(bob)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('add operator by non-admin', async () => {
        await expectRevert(
          relayManager.addOperator(bob, {from: bob}),
          'RelayManagerETH: CALLER_NO_OWNER'
        );
      });
      it('remove operator by non-admin', async () => {
        await relayManager.addOperator(bob);
        await expectRevert(
          relayManager.removeOperator(bob, {from: bob}),
          'RelayManagerETH: CALLER_NO_OWNER'
        );
      });
    });
  });

  describe('#SendBatch', async () => {
    let adminFee, gasFee, receiveAmount;
    const sendAmount = web3.utils.toWei(new BN(100));
    const dummyDepositHash = '0xf408509b00caba5d37325ab33a92f6185c9b5f007a965dfbeff7b81ab1ec871b';
    const polygonChainId = new BN(137);

    it('deposit', async () => {
      expectEvent(
        await relayManager.deposit(bob, sendAmount, polygonChainId, {from: alice}),
        'Deposited'
      );
      await ido.balanceOf(relayManager.address).then(res => {
        expect(res.toString()).to.eq('100000000000000000000');
      });
    });

    it('send', async () => {
      await relayManager.sendBatch([bob], [sendAmount], [dummyDepositHash], 1, {from: bob});
      adminFee = await relayManager.adminFeeAccumulated();
      expect(adminFee.toString()).to.eq('300000000000000000');
      gasFee = await relayManager.gasFeeAccumulated();
      receiveAmount = sendAmount.sub(adminFee).sub(gasFee);
      await ido.balanceOf(bob).then(res => {
        expect(res.toString()).to.eq(receiveAmount.toString());
      });
    });
    it('non-operator call sendBatch', async () => {
      await expectRevert(
        relayManager.sendBatch([bob], [sendAmount], [dummyDepositHash], 1, {from: carol}),
        'RelayManagerETH: CALLER_NO_OPERATOR_ROLE'
      );
    });
    it('bad call sendBatch', async () => {
        await expectRevert(
          relayManager.sendBatch([bob], [], [], 1, {from: bob}),
          'RelayManagerETHBatch: PARAMS_LENGTH_MISMATCH'
        );
      });
  });
});
