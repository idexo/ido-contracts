const IDO1 = artifacts.require('IDO1');
const IDOSale = artifacts.require('IDOSale');
const ERC20Mock6 = artifacts.require('ERC20Mock6');
const BN = web3.utils.BN;

module.exports = async function (deployer) {
  await deployer.deploy(
    IDO1,
    'Easy Token',
    'EASY'
  );
  const easy = await IDO1.deployed();

  await deployer.deploy(
    ERC20Mock6,
    'Tether USD',
    'USDT'
  );
  const mockUSDT = await ERC20Mock6.deployed();

  const currentTime = Math.floor(Date.now() / 1000);
  const startTime = currentTime + 1800;
  const endTime = startTime + 3600;
  await deployer.deploy(
    IDOSale,
    easy.address,
    mockUSDT.address,
    450000,
    web3.utils.toWei(new BN(11111)),
    startTime,
    endTime
  );
};
