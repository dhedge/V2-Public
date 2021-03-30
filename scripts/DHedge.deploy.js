const hre = require('hardhat')
// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = '0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83';
const TESTNET_DAO = '0xab0c25f17e993F90CaAaec06514A2cc28DEC340b';

async function main () {
  const ethers = hre.ethers
  const l2ethers = hre.l2ethers

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer address: ', await signer.getAddress())

  // Deploy PoolFactoryLogic
  const PoolFactoryLogic = await l2ethers.getContractFactory('PoolFactory')

  const poolFactoryLogic = await PoolFactoryLogic.deploy()
  let tx = await poolFactoryLogic.deployed()

  console.log("tx: ", tx.deployTransaction.hash)
  console.log('poolFactoryLogic deployed to:', poolFactoryLogic.address)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(poolFactoryLogic.address)
  )

  // Deploy PoolManagerLogic
  const PoolManagerLogic = await l2ethers.getContractFactory('PoolManagerLogic')

  const poolManagerLogic = await PoolManagerLogic.deploy()
  tx = await poolManagerLogic.deployed()

  console.log("tx: ", tx.deployTransaction.hash)
  console.log('PoolManagerLogic deployed to:', poolManagerLogic.address)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(poolManagerLogic.address)
  )
  console.log('numberOfSupportedAssets:', await poolManagerLogic.numberOfSupportedAssets())

  // Deploy PoolLogic
  const PoolLogic = await l2ethers.getContractFactory('PoolLogic')

  const poolLogic = await PoolLogic.deploy()
  tx = await poolLogic.deployed()

  console.log("tx: ", tx.deployTransaction.hash)
  console.log('poolLogic deployed to:', poolLogic.address)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(poolLogic.address)
  )
  console.log('tokenPriceAtLastFeeMint:', await poolLogic.tokenPriceAtLastFeeMint())

  // Deploy ProxyAdmin
  const ProxyAdmin = await l2ethers.getContractFactory('ProxyAdmin')
  const proxyAdmin = await ProxyAdmin.deploy()
  tx = await proxyAdmin.deployed()

  console.log('ProxyAdmin deployed to:', proxyAdmin.address)
  console.log("tx: ", tx.deployTransaction.hash)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(proxyAdmin.address)
  )

  console.log('ProxyAdmin owner:', await proxyAdmin.owner())

  // Deploy poolFactory Proxy
  const PoolFactoryProxy = await l2ethers.getContractFactory('OZProxy')
  const poolFactoryProxy = await PoolFactoryProxy.deploy(poolFactoryLogic.address, proxyAdmin.address, "0x")
  tx = await poolFactoryProxy.deployed()

  console.log('poolFactoryProxy deployed to:', poolFactoryProxy.address)
  console.log("tx: ", tx.deployTransaction.hash)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(poolFactoryProxy.address)
  )

  const poolFactory = await PoolFactoryLogic.attach(poolFactoryProxy.address)
  tx = await poolFactory.initialize(KOVAN_ADDRESS_RESOLVER, poolLogic.address, poolManagerLogic.address, TESTNET_DAO)
  console.log("tx: ", tx.hash)
  let daoFee = await poolFactory.getDaoFee()
  daoFee.map(each => { console.log("daoFee: ", each.toString()) })

  tx = await poolFactory.createFund(
    false, signer.address, 'Barren Wuffet', 'Test Fund', new ethers.BigNumber.from('5000'), []
  );
  // TX got Reverted
  console.log("tx: ", tx)

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })

