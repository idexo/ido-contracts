const IDO = artifacts.require('IDO');

module.exports = async function (deployer) {
  await deployer.deploy(
    IDO,
  );
};
