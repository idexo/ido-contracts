const { ethers } = require('hardhat');
const { expect } = require('chai');

async function setup() {
  const [owner, alice, bob, carol] = await ethers.getSigners();
  const Whitelist = await ethers.getContractFactory('Whitelist');
  const contract = await Whitelist.deploy();
  return {contract, alice, bob, carol};
}

describe('Whitelist', async () => {
  let contract;
  let owner, alice, bob, carol;

  describe('addWhitelist()', async () => {
    it('expect to add whitelist', async () => {
      ({contract, owner, alice, bob, carol} = await setup());
      await contract.addWhitelist([alice.address, ethers.constants.AddressZero]);

      // check state variable update
      expect(await contract.whitelist(alice.address)).to.eq(true);
    });
    it('stress test - adding 500 addresses to whitelist', async () => {
      let wh = new Array(500).fill("0x00000000000000000000000000000000000");
      for (let i = 0; i < wh.length; i++) wh[i] += (i+10000).toString();
      await contract.addWhitelist(wh);
    });
    describe('reverts if', async () => {
      it('non owner call', async () => {
        await expect(contract.connect(alice).addWhitelist([alice.address, ethers.constants.AddressZero]))
          .to.be.revertedWith('Ownable: caller is not the owner');
      });
    });
  });

  describe('removeWhitelist()', async () => {
    it('expect to remove whitelist', async () => {
      ({contract, owner, alice, bob, carol} = await setup());
      await contract.removeWhitelist([alice.address, ethers.constants.AddressZero]);

      // check state variable update
      expect(await contract.whitelist(alice.address)).to.eq(false);
    });
    describe('reverts if', async () => {
      it('non owner call', async () => {
        await expect(contract.connect(alice).removeWhitelist([alice.address, ethers.constants.AddressZero]))
          .to.be.revertedWith('Ownable: caller is not the owner');
      });
    });
  });
});
