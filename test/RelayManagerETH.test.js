// Initiate `ownerPrivateKey` with the third account private key on test evm

const { expect } = require('chai');
const { ethers } = require('hardhat');
const ethCrypto = require('eth-crypto');
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

const signer1 = '0xe6Dba9e3f988902d5b407615c19e89D756396447';
const signer1Key = '0x34cee9ead792f332d133b1bfc7a915438e41bc42cec0ef3f4f79b74877a16012';
const signer2 = '0x6Fda6B0E6Adf2664D9b30199A54B77b050874656';
const signer2Key = '0x16f8c6cc563f28f8b213b85a0f7149243794e3b0f87519833b08f6838892121c';

const ethSign = msgHash => ethers.utils.solidityKeccak256(
  ['bytes'],
  [ethers.utils.solidityPack(
      ['string', 'bytes'],
      ['\x19Ethereum Signed Message:\n32', msgHash]
  )]
);

contract('RelayManagerETH', async accounts => {
  let relayManager;
  let ido;
  const [alice, bob, carol, bridge] = accounts;
  const idoName = 'Idexo Token';
  const idoSymbol = 'IDO';
  const ownerPrivateKey = Buffer.from('08c83289b1b8cce629a1e58b65c25b1c8062d5c9ec6375dc8265ad13ba25c630', 'hex');

  before(async () => {
    ido = await ERC20PermitMock.new(idoName, idoSymbol);
    relayManager = await RelayManagerETH.new(ido.address, new BN(30), bridge, new BN(1), [signer1]);

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
    it('send', async () => {
      // Accept cross-chain transfer from Polygon (carol => bob)

      await expectRevert(
        relayManager.send(alice, bob, sendAmount, 1, [dummyDepositHash], {from: bob}),
        'ECDSA: invalid signature length'
      );
    });
    it('isSigner', async () => {
      await relayManager.isSigner(bob).then(res => {
        expect(res.toString()).to.eq('false');
      });
    });
  });

  describe('Setters', async () => {
    it('expect to add signer', async () => {
      msgHash = ethers.utils.solidityKeccak256(
        ['bytes'],
        [ethers.utils.solidityPack(
          ['address'],
          [signer2]
        )]
      );
      sig1 = ethCrypto.sign(signer1Key, ethSign(msgHash));
      await relayManager.addSigner(signer2, [sig1]);
      await relayManager.signerLength().then(res => {
        expect(res.toString()).to.eq('2');
      });
    });
    it('expect to remove signer', async () => {
      msgHash = ethers.utils.solidityKeccak256(
        ['bytes'],
        [ethers.utils.solidityPack(
          ['address'],
          [signer2]
        )]
      );
      sig1 = ethCrypto.sign(signer1Key, ethSign(msgHash));
      await relayManager.removeSigner(signer2, [sig1]);
      await relayManager.signerLength().then(res => {
        expect(res.toString()).to.eq('1');
      });
    });
    it('expect to set adminFee', async () => {
      msgHash = ethers.utils.solidityKeccak256(
        ['bytes'],
        [ethers.utils.solidityPack(
          ['uint256'],
          [ethers.utils.parseEther('5')]
        )]
      );
      sig1 = ethCrypto.sign(signer1Key, ethSign(msgHash));
      await relayManager.setAdminFee(ethers.utils.parseEther('5'), [sig1]);
    });
    it('expect to set threshold', async () => {
      msgHash = ethers.utils.solidityKeccak256(
        ['bytes'],
        [ethers.utils.solidityPack(
          ['uint8'],
          [1]
        )]
      );
      sig1 = ethCrypto.sign(signer1Key, ethSign(msgHash));
      await relayManager.setThreshold(1, [sig1]);
    });
  });

  describe('#Ownership', async () => {
    it('should transfer ownership', async () => {
      await relayManager.transferOwnership(bob);
      await relayManager.acceptOwnership({from: bob});
      expect(await relayManager.owner()).to.eq(bob);
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

  describe('#Signatures', async () => {
    describe('reverts if', async () => {
      it('no signatures on setAdminFee', async () => {
        await expectRevert(
          relayManager.setAdminFee(1, [], {from: bob}),
          'RelayManager2Secure: INVALID_SIGNATURE'
        );
      });
      it('no signatures on setThreshold', async () => {
         await expectRevert(
          relayManager.setThreshold(2, [], {from: bob}),
          'RelayManager2Secure: INVALID_SIGNATURE'
        );
      });
      it('no signatures on addSigner', async () => {
        await expectRevert(
         relayManager.addSigner(alice, [], {from: bob}),
         'RelayManager2Secure: INVALID_SIGNATURE'
       );
      });
      it('no signatures on removeSigner', async () => {
        await expectRevert(
         relayManager.removeSigner(alice, [], {from: bob}),
         'RelayManager2Secure: INVALID_SIGNATURE'
       );
      });
      it('no signatures on setBridgeWallet', async () => {
        await expectRevert(
         relayManager.setBridgeWallet(alice, [], {from: bob}),
         'RelayManager2Secure: INVALID_SIGNATURE'
       );
      });
      it('no signatures on send', async () => {
        await expectRevert(
         relayManager.send(alice, bob, web3.utils.toWei(new BN(100)), 0, [], {from: bob}),
         'RelayManager2Secure: INVALID_SIGNATURE'
       );
      });
    });
  });
});
