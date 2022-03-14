import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { checkAlmostSame, units } from "../../TestHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  IBalancerV2Vault__factory,
  IERC20,
  IERC20__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { createFund } from "../utils/createFund";
import { assets, assetsBalanceOfSlot, balancer } from "../../../config/chainData/polygon-data";
import { getAccountToken } from "../utils/getAccountTokens";
import { deployContracts } from "../utils/deployContracts";

use(solidity);

describe("Balancer V2 Test", function () {
  let WETH: IERC20,
    USDC: IERC20,
    USDT: IERC20,
    BALANCER: IERC20,
    BALANCERLP_STABLE: IERC20,
    BALANCERLP_WETH_BALANCER: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress, user: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault__factory.abi);

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    USDC = deployments.assets.USDC;
    USDT = deployments.assets.USDT;
    WETH = deployments.assets.WETH;
    BALANCER = deployments.assets.BALANCER!;
    BALANCERLP_STABLE = deployments.assets.BALANCERLP_STABLE!;
    BALANCERLP_WETH_BALANCER = deployments.assets.BALANCERLP_WETH_BALANCER!;

    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await getAccountToken(units(10000), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.usdt, isDeposit: true },
      { asset: assets.weth, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;
    // Deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, units(200, 6));
    await poolLogicProxy.deposit(assets.usdc, units(200, 6));
  });
  it("Should be able to approve", async () => {
    let approveABI = iERC20.encodeFunctionData("approve", [assets.usdc, (200e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.balancer, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );
    approveABI = iERC20.encodeFunctionData("approve", [balancer.v2Vault, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });
  it("should be able to swap tokens on balancer - swap exactInput.", async () => {
    const poolId = "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012";
    const kind = 0;
    const assetIn = assets.usdc;
    const assetOut = assets.usdt;
    const amount = units(1, 6);
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limit = "990000";
    let swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assets.dai, amount, "0x"],
      [sender, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );
    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [assets.dai, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "sender is not pool",
    );
    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, assets.dai, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "recipient is not pool",
    );
    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, recipient, false],
      "950000",
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "slippage limit exceed",
    );
    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx);
    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter).to.equal(usdcBalanceBefore.sub(amount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(amount));
    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });
  it("should be able to swap tokens on balancer - swap exactOutput.", async () => {
    const poolId = "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012";
    const kind = 1;
    const assetIn = assets.usdc;
    const assetOut = assets.usdt;
    const amount = units(1, 6);
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limit = "1010000";

    let swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assets.dai, amount, "0x"],
      [sender, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );
    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [assets.dai, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "sender is not pool",
    );
    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, assets.dai, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "recipient is not pool",
    );
    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, recipient, false],
      "1050000",
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx)).to.be.revertedWith(
      "slippage limit exceed",
    );
    swapTx = iBalancerV2Vault.encodeFunctionData("swap", [
      [poolId, kind, assetIn, assetOut, amount, "0x"],
      [sender, false, recipient, false],
      limit,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx);
    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(amount));
    expect(usdtBalanceAfter).to.equal(usdtBalanceBefore.add(amount));
    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });
  it("should be able to swap tokens on balancer - batchSwap exactInput.", async () => {
    const kind = 0;
    const amount = units(1, 6);
    const pools = [
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
    ];
    const assetsArray = [assets.usdc, assets.usdt];
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limits = ["1000000", "-990000"];

    let swapTx = iBalancerV2Vault.encodeFunctionData("batchSwap", [
      kind,
      pools,
      assetsArray,
      [sender, false, recipient, false],
      limits,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx);
    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter).to.equal(usdcBalanceBefore.sub(amount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(amount));
    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });
  it("should be able to swap tokens on balancer - batchSwap exactOutput.", async () => {
    const kind = 1;
    const amount = units(1, 6);
    const pools = [
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
      ["0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012", 0, 1, "500000", "0x"],
    ];
    const assetsArray = [assets.usdc, assets.usdt];
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const limits = ["1010000", "-1000000"];

    let swapTx = iBalancerV2Vault.encodeFunctionData("batchSwap", [
      kind,
      pools,
      assetsArray,
      [sender, false, recipient, false],
      limits,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, swapTx);
    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(amount));
    expect(usdtBalanceAfter).to.equal(usdtBalanceBefore.add(amount));
    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });
  it("should be able to join pool on balancer.", async () => {
    await poolManagerLogicProxy
      .connect(manager)
      .changeAssets([{ asset: balancer.stablePools.BPSP, isDeposit: false }], []);
    const poolId = "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012";
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const assetsArray = [assets.usdc, assets.dai, assets.miMatic, assets.usdt];
    const amount = units(1, 6);
    const maxAmountsIn = [amount, 0, 0, amount];

    let joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        [amount, 0, amount, amount],
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, [amount, 0, amount, amount], 1]),
        false,
      ],
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx)).to.be.revertedWith(
      "unsupported asset",
    );
    joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      assets.dai,
      recipient,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, maxAmountsIn, 1]),
        false,
      ],
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx)).to.be.revertedWith(
      "sender is not pool",
    );
    joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      sender,
      assets.dai,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, maxAmountsIn, 1]),
        false,
      ],
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx)).to.be.revertedWith(
      "recipient is not pool",
    );
    joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, maxAmountsIn, 1]),
        false,
      ],
    ]);
    let approveABI = iERC20.encodeFunctionData("approve", [balancer.v2Vault, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdt, approveABI);
    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx);
    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter).to.equal(usdcBalanceBefore.sub(amount));
    expect(usdtBalanceAfter).to.equal(usdtBalanceBefore.sub(amount));
    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });
  it("should be able to exit pool on balancer.", async () => {
    const poolId = "0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000012";
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const assetsArray = [assets.usdc, assets.dai, assets.miMatic, assets.usdt];
    const amount = units(1, 6);
    const minAmountsOut = [0, 0, 0, 0];

    let exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256", "uint256"],
          [0, await BALANCERLP_STABLE.balanceOf(poolLogicProxy.address), 2],
        ),
        false,
      ],
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx)).to.be.revertedWith(
      "unsupported asset",
    );
    exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      assets.dai,
      recipient,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256", "uint256"],
          [0, await BALANCERLP_STABLE.balanceOf(poolLogicProxy.address), 0],
        ),
        false,
      ],
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx)).to.be.revertedWith(
      "sender is not pool",
    );
    exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      sender,
      assets.dai,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256", "uint256"],
          [0, await BALANCERLP_STABLE.balanceOf(poolLogicProxy.address), 0],
        ),
        false,
      ],
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx)).to.be.revertedWith(
      "recipient is not pool",
    );
    exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256", "uint256"],
          [0, await BALANCERLP_STABLE.balanceOf(poolLogicProxy.address), 0],
        ),
        false,
      ],
    ]);
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add(amount.mul(2)));
    expect(usdtBalanceAfter).to.be.equal(usdtBalanceBefore);
    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });
  it("should be able to join weth-bal pool on balancer.", async () => {
    // Deposit 0.1 WETH
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.weth, isDeposit: true }], []);
    await WETH.approve(poolLogicProxy.address, units(1).div(10));
    await poolLogicProxy.deposit(assets.weth, units(1).div(10));
    await poolManagerLogicProxy
      .connect(manager)
      .changeAssets([{ asset: balancer.pools.bal80weth20, isDeposit: false }], []);
    const poolId = await (await ethers.getContractAt("IBalancerWeightedPool", balancer.pools.bal80weth20)).getPoolId();
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const assetsArray = (await (await ethers.getContractAt("IBalancerV2Vault", balancer.v2Vault)).getPoolTokens(poolId))
      .tokens;
    const amount = units(1).div(10);
    const maxAmountsIn = [amount, 0];

    const joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256", "uint256"], [2, units(1), 0]),
        false,
      ],
    ]);
    let approveABI = iERC20.encodeFunctionData("approve", [balancer.v2Vault, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);
    const lpBalanceBefore = ethers.BigNumber.from(await BALANCERLP_WETH_BALANCER.balanceOf(poolLogicProxy.address));
    const wethBalanceBefore = ethers.BigNumber.from(await WETH.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx);
    const lpBalanceAfter = ethers.BigNumber.from(await BALANCERLP_WETH_BALANCER.balanceOf(poolLogicProxy.address));
    expect(lpBalanceAfter).to.gt(lpBalanceBefore);
    const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
    expect(wethBalanceAfter).to.lt(wethBalanceBefore);
    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });
  it("should be able to exit weth-bal pool on balancer.", async () => {
    const poolId = await (await ethers.getContractAt("IBalancerWeightedPool", balancer.pools.bal80weth20)).getPoolId();
    const sender = poolLogicProxy.address;
    const recipient = poolLogicProxy.address;
    const assetsArray = (await (await ethers.getContractAt("IBalancerV2Vault", balancer.v2Vault)).getPoolTokens(poolId))
      .tokens;
    const minAmountsOut = [0, 0];

    const exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      sender,
      recipient,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256"],
          [1, await BALANCERLP_WETH_BALANCER.balanceOf(poolLogicProxy.address)],
        ),
        false,
      ],
    ]);
    const lpBalanceBefore = ethers.BigNumber.from(await BALANCERLP_WETH_BALANCER.balanceOf(poolLogicProxy.address));
    const wethBalanceBefore = ethers.BigNumber.from(await WETH.balanceOf(poolLogicProxy.address));
    const balancerBalanceBefore = ethers.BigNumber.from(await BALANCER.balanceOf(poolLogicProxy.address));
    const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    await expect(poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx)).to.be.revertedWith(
      "unsupported asset",
    );
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.balancer, isDeposit: false }], []);
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx);
    const lpBalanceAfter = ethers.BigNumber.from(await BALANCERLP_WETH_BALANCER.balanceOf(poolLogicProxy.address));
    expect(lpBalanceAfter).to.lt(lpBalanceBefore);
    const wethBalanceAfter = ethers.BigNumber.from(await WETH.balanceOf(poolLogicProxy.address));
    const balancerBalanceAfter = ethers.BigNumber.from(await BALANCER.balanceOf(poolLogicProxy.address));
    expect(wethBalanceAfter).to.gt(wethBalanceBefore);
    expect(balancerBalanceAfter).to.gt(balancerBalanceBefore);
    const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
    checkAlmostSame(totalFundValueBefore, totalFundValueAfter);
  });
});
