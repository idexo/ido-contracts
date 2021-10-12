# Idexo Core Contracts
Supported chains: Ethereum, Binance Smart Chain, Polygon and Avalanche

## Dependencies
- NPM: https://nodejs.org
- Truffle: https://www.trufflesuite.com/
- Ganache CLI: https://github.com/trufflesuite/ganache

## Step 1. Clone the project
`git clone https://github.com/idexo/ido-contracts`

## Step 2. Install dependencies
```
$ cd avalanche
$ npm install
```

## Step 3. Start Ganache
`$ ganache-cli`

## Step 4. Compile & Test
```
$ truffle compile
$ truffle test
```

## Step 5. Flatten
```
$ npm run build-contracts
```

## Step 6. Deploy
```
$ truffle migrate --network ropsten
$ truffle migrate --network mainnet
```

## Features

### Staking
- StakePoolCombined
- StakeMirrorNFT

### Bridging
- LiquidityPoolManager

### Voting
- Voting
- MultipleVoting
