const WIDO = artifacts.require('WIDO');
const RelayManager2 = artifacts.require('RelayManager2');

module.exports = async function (deployer) {
  await deployer.deploy(
    RelayManager2,
    `0x21a97B14499C76731062a3f4c1Fd67CD04D62980`,
    500,
  );
};
