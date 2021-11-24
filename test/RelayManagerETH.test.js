// Initiate `ownerPrivateKey` with the third account private key on test evm

const { expect } = require('chai');
const {
  BN,
  constants,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');
const {
  PERMIT_TYPEHASH,
  getPermitDigest,
  getDomainSeparator,
  sign
} = require('./helpers/signature');

const RelayManagerETH = artifacts.require('RelayManagerETH');
const ERC20PermitMock = artifacts.require('ERC20PermitMock');

contract('RelayManagerETH', async accounts => {
  let relayManager;
  let ido;
  const [alice, bob, carol, bridge] = accounts;
  const idoName = 'Idexo Token';
  const idoSymbol = 'IDO';
  const ownerPrivateKey = Buffer.from('08c83289b1b8cce629a1e58b65c25b1c8062d5c9ec6375dc8265ad13ba25c630', 'hex');

  before(async () => {
    ido = await ERC20PermitMock.new(idoName, idoSymbol);
    relayManager = await RelayManagerETH.new(ido.address, new BN(30), bridge, new BN(2), [alice, carol]);

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

  describe('cross-chain transfer', async () => {
    let adminFee, gasFee, receiveAmount;
    const sendAmount = web3.utils.toWei(new BN(100));
    const dummyDepositHash = '0xf408509b00caba5d37325ab33a92f6185c9b5f007a965dfbeff7b81ab1ec871b';
    const polygonChainId = new BN(137);

    it('deposit', async () => {
      // Start transfer to Polygon (alice => bob)
      expectEvent(
        await relayManager.deposit(bob, sendAmount, polygonChainId, {from: alice}),
        'Deposited'
      );
      await ido.balanceOf(relayManager.address).then(res => {
        expect(res.toString()).to.eq('100000000000000000000');
      });
    });
    /*it('permitAndDeposit', async () => {
      let chainId;
      await ido.getChainId().then(res => {
        chainId = res.toNumber();
      });
      // Create the approval request
      const approve = {
        owner: carol,
        spender: relayManager.address,
        value: 100,
      };
      // deadline as much as you want in the future
      const deadline = 100000000000000;
      // Get the user's nonce
      const nonce = await ido.nonces(carol);
      // Get the EIP712 digest
      console.log(nonce.toNumber())
      const digest = getPermitDigest(idoName, ido.address, chainId, approve, nonce.toNumber(), deadline);
      // Sign it
      // NOTE: Using web3.eth.sign will hash the message internally again which
      // we do not want, so we're manually signing here
      const { v, r, s } = sign(digest, ownerPrivateKey);
      const permitOptions = { nonce, deadline, v, r, s };
      // Approve it
      expectEvent(
        await relayManager.permitAndDeposit(bob, new BN(100), polygonChainId, permitOptions, {from: carol}),
        'Deposited'
      );
    });
    it('send', async () => {
      // Accept cross-chain transfer from Polygon (carol => bob)

      expectEvent(
        await relayManager.send(bob, sendAmount, dummyDepositHash, 1, {from: bob}),
        'Sent'
      );
      adminFee = await relayManager.adminFeeAccumulated();
      expect(adminFee.toString()).to.eq('300000000000000000');
      gasFee = await relayManager.gasFeeAccumulated();
      console.log('Gas fee:', gasFee.toString());
      receiveAmount = sendAmount.sub(adminFee).sub(gasFee);
      await ido.balanceOf(bob).then(res => {
        expect(res.toString()).to.eq(receiveAmount.toString());
      });
    });*/
  });

  describe('#Ownership', async () => {
    it('should transfer ownership', async () => {
      await relayManager.transferOwnership(bob);
      await relayManager.acceptOwnership({from: bob});
      expect(await relayManager.owner()).to.eq(bob);
      /*expectEvent(
        await relayManager.setAdminFee(1,{from: bob}),
        'AdminFeeChanged'
      )*/
    });
    describe('reverts if', async () => {
        it('non-owner call setMinTransferAmount', async () => {
            await expectRevert(
              relayManager.setMinTransferAmount(1, {from: carol}),
              'RelayManagerETH: CALLER_NO_OWNER'
            );
          });
        it('non-operator call setAdminFee', async () => {
           await expectRevert(
            relayManager.setAdminFee(1, [], {from: carol}),
            'RelayManagerETH: CALLER_NO_OPERATOR_ROLE'
          );
        });
        it('non-owner call transferOwnership', async () => {
        await expectRevert(
          relayManager.transferOwnership(bob, {from: carol}),
          'RelayManagerETH: CALLER_NO_OWNER'
        );
      });
      it('call transferOwnership with zero address', async () => {
        await expectRevert(
          relayManager.transferOwnership(constants.ZERO_ADDRESS, {from: bob}),
          'RelayManagerETH: INVALID_ADDRESS'
        );
      });
      it('non owner call renounceOwnership', async () => {
        await expectRevert(
            relayManager.renounceOwnership({from: carol}),
          'RelayManagerETH: CALLER_NO_OWNER'
        );
      });
      it('non new owner call acceptOwnership', async () => {
        await relayManager.transferOwnership(alice, {from: bob});
        await expectRevert(
          relayManager.acceptOwnership({from: carol}),
          'RelayManagerETH: CALLER_NO_NEW_OWNER'
        );
        expectEvent(
          await relayManager.renounceOwnership({from: bob}),
          'OwnershipTransferred'
        )
      })
    });
  });
});
