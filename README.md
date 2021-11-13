# Idexo Core Contracts
Supported chains: Ethereum, Binance Smart Chain, Polygon and Avalanche
____
[![codecov](https://codecov.io/gh/idexo/ido-contracts/branch/main/graph/badge.svg?token=HLKWVOLF1E)](https://codecov.io/gh/idexo/ido-contracts)

## Dependencies
- NPM: https://nodejs.org
- Truffle: https://www.trufflesuite.com/

## Step 1. Clone the project
```
git clone https://github.com/idexo/ido-contracts
```

## Step 2. Install dependencies
```
npm install
```

## Step 3. Compile & Test
```
npm run compile
npm run test
```

## Step 4. Flatten
```
npm run build-contracts
```

## Step 5. Deploy
```
truffle migrate --network ropsten
truffle migrate --network mainnet
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
