const { ethers } = require('hardhat');
const { expect } = require('chai');

describe('FactoryOperatorable', async () => {
  let contract, alice, bob;

  before(async () => {
    [alice, bob] = await ethers.getSigners();
    contract = await (await ethers.getContractFactory('FactoryOperatorable')).deploy(alice.address, alice.address);
  });

  describe('addOperator()', async () => {
    it('expect to add operator', async () => {
      await contract.addOperator(alice.address)
      expect(await contract.checkOperator(alice.address)).to.eq(true);
    });
    describe('reverts if', async () => {
      it('non admin call', async () => {
        await expect(contract.connect(bob).addOperator(bob.address))
          .to.be.revertedWith('Operatorable: CALLER_NO_ADMIN_ROLE');
      });
    });
  });

  describe('removeOperator()', async () => {
    it('expect to remove operator', async () => {
      await contract.removeOperator(alice.address)
      expect(await contract.checkOperator(alice.address)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('non owner call', async () => {
        await expect(contract.connect(bob).removeOperator(bob.address))
          .to.be.revertedWith('Operatorable: CALLER_NO_ADMIN_ROLE');
      });
    });
  });
});
