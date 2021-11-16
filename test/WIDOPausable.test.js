const { ethers } = require('hardhat');
const { expect } = require('chai');

const setup = async () => {
  const [owner, relayer, alice, bob, carol] = await ethers.getSigners();
  const WIDOPausable = await ethers.getContractFactory('WIDOPausable');
  const contract = await WIDOPausable.deploy();
  return {contract, owner, relayer, alice, bob, carol};
};

describe('WIDOPausable', () => {
  let contract;
  let owner, relayer, alice, bob, carol;

  describe('Token', async () => {
    it('expect to mint and burn', async () => {
      ({contract, owner, relayer, alice, bob, carol} = await setup());      
      await contract.setRelayer(relayer.address);
      await expect(contract.connect(relayer).mint(alice.address, ethers.utils.parseEther('100')))
        .to.emit(contract, 'Transfer');
      await expect(contract.connect(relayer).burn(alice.address, ethers.utils.parseEther('100')))
        .to.emit(contract, 'Transfer');
      await contract.balanceOf(alice.address).then(res => {
        expect(res.toString()).to.eq('0');
      });
    });
    describe('reverts if', async () => {
      it('non-owner call setRelayer', async () => {
        await expect(contract.connect(bob).setRelayer(bob.address))
          .to.be.revertedWith('Ownable: CALLER_NO_OWNER');
      });
      it('non-relayer call mint/burn', async () => {
        await expect(contract.connect(bob).mint(alice.address, ethers.utils.parseEther('100')))
          .to.be.revertedWith('WIDOPausable: CALLER_NO_RELAYER');
        await expect(contract.connect(bob).burn(alice.address, ethers.utils.parseEther('100')))
          .to.be.revertedWith('WIDOPausable: CALLER_NO_RELAYER');
      });
    });
  });

  describe('#Ownership', async () => {
    it('should transfer ownership', async () => {
      await contract.transferOwnership(bob.address);
      await contract.connect(bob).acceptOwnership();
      expect(await contract.owner()).to.eq(bob.address);
    });
    describe('reverts if', async () => {
      it('non-owner call transferOwnership', async () => {
        await expect(contract.connect(carol).transferOwnership(bob.address))
          .to.be.revertedWith('Ownable: CALLER_NO_OWNER');
      });
      it('call transferOwnership with zero address', async () => {
        await expect(contract.connect(bob).transferOwnership(ethers.constants.AddressZero))
          .to.be.revertedWith('Ownable: INVALID_ADDRESS');
      });
      it('non new owner call acceptOwnership', async () => {
        await contract.connect(bob).transferOwnership(alice.address);
        await expect(contract.connect(carol).acceptOwnership())
          .to.be.revertedWith('Ownable: CALLER_NO_NEW_OWNER');
      })
    });
  });
});
