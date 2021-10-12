const IDO = artifacts.require('IDO');
const IDOSale = artifacts.require('IDOSale');
const BN = web3.utils.BN;

module.exports = async function (deployer) {
  const ido = await IDO.deployed();

  const currentTime = Math.floor(Date.now() / 1000);
  const startTime = currentTime + 1800;
  const endTime = startTime + 3600;
  await deployer.deploy(
    IDOSale,
    ido.address,
    '0xdAC17F958D2ee523a2206206994597C13D831ec7',
    450000,
    web3.utils.toWei(new BN(11111)),
    startTime,
    endTime
  );
};
