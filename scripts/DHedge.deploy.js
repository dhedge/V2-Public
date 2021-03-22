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

  // Deploy DHedgeManagerLogic
  const DHedgeManagerLogic = await l2ethers.getContractFactory('DHedgeManagerLogic', {
    signer: (await ethers.getSigners())[0]
  })

  const dHedgeManagerLogic = await DHedgeManagerLogic.deploy()
  let tx = await dHedgeManagerLogic.deployed()

  console.log("tx: ", tx.deployTransaction.hash)
  console.log('DHedgeManagerLogic deployed to:', dHedgeManagerLogic.address)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(dHedgeManagerLogic.address)
  )
  console.log('numberOfSupportedAssets:', await dHedgeManagerLogic.numberOfSupportedAssets())

  // Deploy DHedge
  const DHedge = await l2ethers.getContractFactory('DHedge', {
    signer: (await ethers.getSigners())[0]
  })

  const dHedge = await DHedge.deploy()
  tx = await dHedge.deployed()

  console.log("tx: ", tx.deployTransaction.hash)
  console.log('DHedge deployed to:', dHedge.address)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(dHedge.address)
  )
  console.log('tokenPriceAtLastFeeMint:', await dHedge.tokenPriceAtLastFeeMint())

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

  // Deploy DHedgeManagerLogic Proxy
  const DHedgeManagerLogicProxy = await l2ethers.getContractFactory('OZProxy', {
    signer: (await ethers.getSigners())[0]
  })
  const dHedgeManagerLogicProxy = await DHedgeManagerLogicProxy.deploy(dHedgeManagerLogic.address, proxyAdmin.address, "0x")
  tx = await dHedgeManagerLogicProxy.deployed()

  console.log('dHedgeManagerLogicProxy deployed to:', dHedgeManagerLogicProxy.address)
  console.log("tx: ", tx.deployTransaction.hash)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(dHedgeManagerLogicProxy.address)
  )

  // Deploy DHedgeProxy
  const DHedgeProxy = await l2ethers.getContractFactory('OZProxy', {
    signer: (await ethers.getSigners())[0]
  })
  const dHedgeProxy = await DHedgeProxy.deploy(dHedge.address, proxyAdmin.address, "0x")
  tx = await dHedgeProxy.deployed()

  console.log('dHedgeProxy deployed to:', dHedgeProxy.address)
  console.log("tx: ", tx.deployTransaction.hash)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(dHedgeProxy.address)
  )

  // const dHedgeManagerLogicUpgrade = await DHedgeManagerLogic.attach(dHedgeManagerLogicProxy.address)
  // dHedgeManagerLogicUpgrade.initialize()
  // let daoFee = await dHedgeFactoryUpgrade.getDaoFee()
  // daoFee.map(each => { console.log("daoFee: ", each.toString()) })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })

