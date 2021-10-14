const RelayManagerETH = artifacts.require('RelayManagerETH');

module.exports = async function (deployer) {
  await deployer.deploy(
    RelayManagerETH,
    '0x975de233452b915219373bff5a49b1c81cd807ef',
    500,
  );
};
