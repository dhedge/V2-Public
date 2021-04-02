## Set Up

Run `npm install`

## Deployment

Run `node scripts/DHedge.deploy.js`

Currently the createFund transaction will get revert (https://kovan-l2-explorer.surge.sh/tx/0xa953b60eedc4cab53e5fad567948bfcc1d271a614783ce303bfc2e6dd0875379)

## Test

Run `npx hardhat test test/PoolFactoryTest.js --network hardhat`

Currently it will fail on PoolManagerLogic.sol:107 when initialising proxy on poolManagerLogic as it would get pass if removing initializer modifier. So something wrong with the initializer.
