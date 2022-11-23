const { ethers } = require('hardhat');
const { expect } = require('chai');

describe('Operatorable', async () => {
  let contract, alice, bob;

  before(async () => {
    [alice, bob] = await ethers.getSigners();
    contract = await (await ethers.getContractFactory('Operatorable')).deploy();
  });

  describe('addOperator()', async () => {
    it('expect to add operator', async () => {
      await contract.addOperator(alice.address)
      expect(await contract.checkOperator(alice.address)).to.eq(true);
    });
    describe('reverts if', async () => {
      it('non owner call', async () => {
        await expect(contract.connect(bob).addOperator(bob.address))
          .to.be.revertedWith('Ownable: caller is not the owner');
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
          .to.be.revertedWith('Ownable: caller is not the owner');
      });
    });
  });
});
