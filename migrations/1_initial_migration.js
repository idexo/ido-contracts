const IDO1 = artifacts.require('IDO1');
const IDOSale = artifacts.require('IDOSale');
const ERC20Mock6 = artifacts.require('ERC20Mock6');
const StakePoolMock = artifacts.require('StakePoolMock');
const BN = web3.utils.BN;

module.exports = async function (deployer) {
  //------------ IDOSale ------------

  // await deployer.deploy(
  //   IDO1,
  //   'Easy Token',
  //   'EASY'
  // );
  // const easy = await IDO1.deployed();

  // await deployer.deploy(
  //   ERC20Mock6,
  //   'Tether USD',
  //   'USDT'
  // );
  // const mockUSDT = await ERC20Mock6.deployed();

  // const currentTime = Math.floor(Date.now() / 1000);
  // const startTime = currentTime + 1800;
  // const endTime = startTime + 3600;
  // await deployer.deploy(
  //   IDOSale,
  //   easy.address,
  //   mockUSDT.address,
  //   450000,
  //   web3.utils.toWei(new BN(11111)),
  //   startTime,
  //   endTime
  // );

  //------------ StakePoolMock ------------
  await deployer.deploy(
    StakePoolMock,
    'Test Stake Token',
    'TST',
    '0x975dE233452b915219373bFf5A49b1C81cD807eF',
    '0xf8bd1920cdd944758771e789474dfb5b5e3f8a0b'
  );
};
