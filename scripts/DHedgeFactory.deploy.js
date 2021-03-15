const hre = require('hardhat')
const { ethers } = require("hardhat");
// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = '0x242a3DF52c375bEe81b1c668741D7c63aF68FDD2';
const TESTNET_DAO = '0xab0c25f17e993F90CaAaec06514A2cc28DEC340b';

async function main () {
  const ethers = hre.ethers
  const l2ethers = hre.l2ethers

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer address: ', await signer.getAddress())

  // Deploy DHedge
  // contracts/DHedge.sol:55:1: Warning: Contract code size exceeds 24576 bytes (a limit introduced in Spurious Dragon). This contract may not be deployable on mainnet. Consider enabling the optimizer (with a low "runs" value!), turning off revert strings, or using libraries.
  // const DHedge = await l2ethers.getContractFactory('DHedge', {
  //   signer: (await ethers.getSigners())[0]
  // })

  // const dHedge = await DHedge.deploy()
  // await dHedge.deployed()

  // console.log('DHedge deployed to:', dHedge.address)
  // console.log(
  //   'deployed bytecode:',
  //   await ethers.provider.getCode(dHedge.address)
  // )
  // console.log('numberOfSupportedAssets:', await dHedge.numberOfSupportedAssets())

  // Deploy DHedgeFactory
  const DHedgeFactory = await l2ethers.getContractFactory("DHedgeFactory", {
    signer: (await ethers.getSigners())[0]
  });
  const dHedgeFactory = await DHedgeFactory.deploy();
  let tx = await dHedgeFactory.deployed();
  console.log("tx: ", tx.deployTransaction.hash)
  console.log("DHedgeFactory deployed to:", dHedgeFactory.address);
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(dHedgeFactory.address)
  )

  // Deploy ProxyAdmin
  const ProxyAdmin = await l2ethers.getContractFactory('ProxyAdmin', {
    signer: (await ethers.getSigners())[0]
  })
  const proxyAdmin = await ProxyAdmin.deploy()
  tx = await proxyAdmin.deployed()

  console.log('ProxyAdmin deployed to:', proxyAdmin.address)
  console.log("tx: ", tx.deployTransaction.hash)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(proxyAdmin.address)
  )

  console.log('ProxyAdmin owner:', await proxyAdmin.owner())

  // Deploy Proxy
  const Proxy = await l2ethers.getContractFactory('Proxy', {
    signer: (await ethers.getSigners())[0]
  })
  const proxy = await Proxy.deploy(dHedgeFactory.address, proxyAdmin.address, "0x")
  tx = await proxy.deployed()

  console.log('Proxy deployed to:', proxy.address)
  console.log("tx: ", tx.deployTransaction.hash)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(proxy.address)
  )

  const dHedgeFactoryUpgrade = await DHedgeFactory.attach(proxy.address)
  await dHedgeFactoryUpgrade.initialize(KOVAN_ADDRESS_RESOLVER, KOVAN_ADDRESS_RESOLVER, TESTNET_DAO)
  let daoFee = await dHedgeFactoryUpgrade.getDaoFee()
  daoFee.map(each => { console.log("daoFee: ", each.toString()) })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })

