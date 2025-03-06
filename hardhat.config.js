/// ENVVAR
// - CI:                output gas report to file instead of stdout
// - COVERAGE:          enable coverage report
// - ENABLE_GAS_REPORT: enable gas report
// - COMPILE_MODE:      production modes enables optimizations (default: development)
// - COMPILE_VERSION:   compiler version (default: 0.8.3)
// - COINMARKETCAP:     coinmarkercat api key for USD value in gas report
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-contract-sizer");

const fs = require('fs');
const path = require('path');
const argv = require('yargs/yargs')()
  .env('')
  .options({
    ci: {
      type: 'boolean',
      default: false,
    },
    coverage: {
      type: 'boolean',
      default: false,
    },
    gas: {
      alias: 'enableGasReport',
      type: 'boolean',
      default: false,
    },
    mode: {
      alias: 'compileMode',
      type: 'string',
      choices: [ 'production', 'development' ],
      default: 'development',
    },
    compiler: {
      alias: 'compileVersion',
      type: 'string',
      default: '0.8.4',
    },
    coinmarketcap: {
      alias: 'coinmarketcapApiKey',
      type: 'string',
    },
  })
  .argv;

require('@nomiclabs/hardhat-truffle5');

if (argv.enableGasReport) {
  require('hardhat-gas-reporter');
}

for (const f of fs.readdirSync(path.join(__dirname, 'hardhat'))) {
  require(path.join(__dirname, 'hardhat', f));
}

const withOptimizations = argv.enableGasReport || argv.compileMode === 'production';

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
      },
      },
      {
        version: "0.8.9",
        settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
      },
      },
      {
        version: "0.8.19",
        settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
        viaIR: true
      },
      }
    ],
    overrides: {
      "contracts/marketplace/direct/*.sol": {
        version: "0.8.9",
      },
      "contracts/paymentsv2/*.sol": {
        version: "0.8.19",
      }
    }
  },
  networks: {
    hardhat: {
      blockGasLimit: 100000000,
      allowUnlimitedContractSize: !withOptimizations,
    },
  },
  gasReporter: {
    currency: 'USD',
    outputFile: argv.ci ? 'gas-report.txt' : undefined,
    coinmarketcap: argv.coinmarketcap,
  },
  contractSizer: {
    runOnCompile: true,
    disambiguatePaths: true,
  }
};

if (argv.coverage) {
  require('solidity-coverage');
  module.exports.networks.hardhat.initialBaseFeePerGas = 0;
}
