const StakeMirrorNFT = artifacts.require('StakeMirrorNFT');

module.exports = async function (deployer) {
  await deployer.deploy(
    StakeMirrorNFT,
    'Stake Mirror Test',
    'SMT',
    'https://example.com/json/',
  );
};
