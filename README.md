# Idexo Open Source Smart Contracts
This repository contains open source smart contracts written and published by [idexo](https://idexo.com). 

These contracts are either used in idexo’s token and community systems and/or used in the idexo [low code SDK / API](https://npmjs.com/idexo-sdk), [Zapier Integration to Web2 Apps](https://zapier.com/apps/idexo/integrations), or [no code SaaS application](https://app.idexo.com/register). 

If there is a contract that you’d like to see that’s not here, you can request it using the Issues tab. If you like the contracts and/or are using them, please give the repo a star and consider sending us a tip in $IDO to 0x647988A14132667Ef09Cef8623ac7EEcE5F62f0f on either the Ethereum or Fantom networks. More info on acquiring $IDO is available at [Coingecko](https://ido.cl/coingecko). For deeper and/or private customizations to suit your use case, you can also inquire about idexo's [custom smart contract development services](https://idexo.com/custom-smart-contract-development.html).

If you would like to contribute your own code to this repo for fame and notoriety, please make pull requests on the repo and the team will review and merge as appropriate. Idexo will soon be announcing a developer incentive program to provide rewards for independent developers to create contracts as requested by the community. 

Idexo supports a number of EVM-based chains as integration partners and makes these contracts available for easy use in its low code SDK / API, Zapier integration, and no code SaaS. Currently supported chains are: 


* Avalanche
* BNBChain
* Dogechain
* Ethereum
* Fantom
* Polygon


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
- StakePoolFlexLock
- StakePoolMultipleRewards
- StakePoolMultipleRewardsTimeLimited

### Soulbound Tokens
- UncappedLinkedSoulbound
- UncappedSBTCommunityRecovery

### Consumable NFT Coupons
- Payments
- ReceiptToken

### Voting With NFTs
- Voting
- MultipleVoting

### Marketplaces
- BaseRoyaltyNFT
- RoyaltyNFT
- DirectSale

### Bridging
- RelayManager
