# OMEA Contract

OMEA allows investors to deposit BUSD and earn rewards based on Hourly Percentage Rate (HPR). The contract also includes a referral system where an investor can earn a percentage of their referred friend's deposit.

## Features

- Deposits and withdrawals of BUSD
- Hourly Percentage Rate (HPR) based rewards for investors
- Referral system where investors can earn a percentage of their referred friend's deposit
- Dev fee, marketing fee and principal fee
- SafeERC20 library for secure token transfers
- Ownable contract with access control
- Reentrancy guard to prevent reentrant attacks
- Error handling for various scenarios

## Constants

The contract defines various constants that govern the functionality of the contract:

- `WITHDRAW_PERIOD`: The period after which an investor can withdraw their deposit
- `REFERRER_REWARD_1`, `REFERRER_REWARD_2`, `REFERRER_REWARD_3`: Referral rewards for different referral levels
- `HPR_5`, `HPR_4`, `HPR_3`, `HPR_2`, `HPR_1`: Hourly Percentage Rate for different deposit levels
- `DEV_FEE`, `MARKETING_FEE`, `PRINCIPAL_FEE`: fees for developer, marketing and principal respectively
  Structs
  The contract uses following structs to store data:

## Setup

- Deploy the OMEA contract to Binance Smart chain
- Set the address of BUSD contract
- Set the dev and marketing wallet addresses
- Launch the contract

## Available Commands

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat run scripts/deploy.ts
```
