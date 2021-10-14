const WIDO = artifacts.require('WIDO');
const RelayManager2 = artifacts.require('RelayManager2');

module.exports = async function (deployer) {
  await deployer.deploy(WIDO);
  const wido = await WIDO.deployed();

  await deployer.deploy(
    RelayManager2,
    wido.address,
    500,
  );
};
