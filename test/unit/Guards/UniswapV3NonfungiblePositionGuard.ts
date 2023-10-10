import { ethers } from "hardhat";
import { expect } from "chai";
import {
  IERC20__factory,
  IMulticall__factory,
  INonfungiblePositionManager__factory,
  MockContract,
  PoolManagerLogic__factory,
  UniswapV3NonfungiblePositionGuard,
} from "../../../types";
import { units } from "../../testHelpers";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

describe("DynamicBonds Test", () => {
  let nonfungiblePositionManager: MockContract, poolLogic: MockContract, poolManagerLogic: MockContract;
  let weth: MockContract, dai: MockContract, usdc: MockContract;
  let uniswapV3NonfungiblePositionGuard: UniswapV3NonfungiblePositionGuard;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iPoolManagerLogic = new ethers.utils.Interface(PoolManagerLogic__factory.abi);
  const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager__factory.abi);
  const iMulticall = new ethers.utils.Interface(IMulticall__factory.abi);
  const tokenId = 0;

  beforeEach(async () => {
    const MockContract = await ethers.getContractFactory("MockContract");

    nonfungiblePositionManager = await MockContract.deploy();
    poolLogic = await MockContract.deploy();
    poolManagerLogic = await MockContract.deploy();
    weth = await MockContract.deploy();
    dai = await MockContract.deploy();
    usdc = await MockContract.deploy();

    const UniswapV3NonfungiblePositionGuard = await ethers.getContractFactory("UniswapV3NonfungiblePositionGuard");
    uniswapV3NonfungiblePositionGuard = await UniswapV3NonfungiblePositionGuard.deploy(1);
    await uniswapV3NonfungiblePositionGuard.deployed();

    await poolManagerLogic.givenCalldataReturnAddress(
      iPoolManagerLogic.encodeFunctionData("poolLogic", []),
      poolLogic.address,
    );

    await poolManagerLogic.givenCalldataReturnBool(
      iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [weth.address]),
      true,
    );
    await poolManagerLogic.givenCalldataReturnBool(
      iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [dai.address]),
      true,
    );
    await poolManagerLogic.givenCalldataReturnBool(
      iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [usdc.address]),
      false,
    );
  });

  it("mint", async () => {
    let mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
      [usdc.address, dai.address, 10000, -414400, -253200, units(2000, 6), units(1), 0, 0, poolLogic.address, deadLine],
    ]);
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(poolManagerLogic.address, nonfungiblePositionManager.address, mintABI),
    ).to.revertedWith("unsupported asset: tokenA");

    mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
      [
        weth.address,
        usdc.address,
        10000,
        -414400,
        -253200,
        units(2000, 6),
        units(1),
        0,
        0,
        poolLogic.address,
        deadLine,
      ],
    ]);
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(poolManagerLogic.address, nonfungiblePositionManager.address, mintABI),
    ).to.revertedWith("unsupported asset: tokenB");

    mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
      [weth.address, dai.address, 10000, -414400, -253200, units(2000, 6), units(1), 0, 0, poolLogic.address, deadLine],
    ]);
    await nonfungiblePositionManager.givenCalldataReturnUint(
      iNonfungiblePositionManager.encodeFunctionData("balanceOf", [poolLogic.address]),
      1,
    );
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(poolManagerLogic.address, nonfungiblePositionManager.address, mintABI),
    ).to.revertedWith("too many uniswap v3 positions");

    mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
      [
        weth.address,
        dai.address,
        10000,
        -414400,
        -253200,
        units(2000, 6),
        units(1),
        0,
        0,
        poolManagerLogic.address,
        deadLine,
      ],
    ]);
    await nonfungiblePositionManager.givenCalldataReturnUint(
      iNonfungiblePositionManager.encodeFunctionData("balanceOf", [poolLogic.address]),
      0,
    );
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(poolManagerLogic.address, nonfungiblePositionManager.address, mintABI),
    ).to.revertedWith("recipient is not pool");

    mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
      [weth.address, dai.address, 10000, -414400, -253200, units(2000, 6), units(1), 0, 0, poolLogic.address, deadLine],
    ]);
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(poolManagerLogic.address, nonfungiblePositionManager.address, mintABI),
    ).to.emit(uniswapV3NonfungiblePositionGuard, "Mint");
  });

  it("increaseLiquidity", async () => {
    const increaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("increaseLiquidity", [
      [tokenId, units(2000, 6), units(1), 0, 0, deadLine],
    ]);
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(
        poolManagerLogic.address,
        nonfungiblePositionManager.address,
        increaseLiquidityABI,
      ),
    ).to.emit(uniswapV3NonfungiblePositionGuard, "IncreaseLiquidity");
  });

  it("decreaseLiquidity", async () => {
    const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
      [tokenId, units(2000, 6), 0, 0, deadLine],
    ]);
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(
        poolManagerLogic.address,
        nonfungiblePositionManager.address,
        decreaseLiquidityABI,
      ),
    ).to.emit(uniswapV3NonfungiblePositionGuard, "DecreaseLiquidity");
  });

  it("burn", async () => {
    const burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(poolManagerLogic.address, nonfungiblePositionManager.address, burnABI),
    ).to.emit(uniswapV3NonfungiblePositionGuard, "Burn");
  });

  it("collect", async () => {
    let collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
      [tokenId, poolManagerLogic.address, units(10000), units(10000)],
    ]);
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(
        poolManagerLogic.address,
        nonfungiblePositionManager.address,
        collectABI,
      ),
    ).revertedWith("recipient is not pool");

    collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
      [tokenId, poolLogic.address, units(10000), units(10000)],
    ]);
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(
        poolManagerLogic.address,
        nonfungiblePositionManager.address,
        collectABI,
      ),
    ).to.emit(uniswapV3NonfungiblePositionGuard, "Collect");
  });

  it("multicall", async () => {
    const wrongABI = iERC20.encodeFunctionData("approve", [nonfungiblePositionManager.address, units(10000, 6)]);
    const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
      [tokenId, units(2000, 6), 0, 0, deadLine],
    ]);
    const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
      [tokenId, poolLogic.address, units(10000), units(10000)],
    ]);
    const burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);

    let multicallABI = iMulticall.encodeFunctionData("multicall", [[decreaseLiquidityABI, wrongABI, burnABI]]);
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(
        poolManagerLogic.address,
        nonfungiblePositionManager.address,
        multicallABI,
      ),
    ).revertedWith("invalid transaction");

    multicallABI = iMulticall.encodeFunctionData("multicall", [[decreaseLiquidityABI, collectABI, burnABI]]);
    await expect(
      uniswapV3NonfungiblePositionGuard.txGuard(
        poolManagerLogic.address,
        nonfungiblePositionManager.address,
        multicallABI,
      ),
    )
      .to.emit(uniswapV3NonfungiblePositionGuard, "DecreaseLiquidity")
      .to.emit(uniswapV3NonfungiblePositionGuard, "Collect")
      .to.emit(uniswapV3NonfungiblePositionGuard, "Burn");
  });
});
