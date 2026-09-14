// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";

import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {SwapperAllTests} from "test/integration/ffi/common/swapper/SwapperAllTests.t.sol";
import {ChainConfig, SwapperTestSetup, Token} from "test/integration/ffi/common/swapper/SwapperTestSetup.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";

contract SwapperTestFFIBase is SwapperAllTests {
  uint256 private constant FORK_BLOCK_NUMBER = 51257584;
  address private constant rETH_CHAINLINK_ORACLE = 0xbe1551fB22F8b877EDF3731CEc6FF703E720Fb85;

  constructor()
    SwapperTestSetup(
      ChainConfig({
        networkAlias: "base",
        forkBlockNumber: FORK_BLOCK_NUMBER,
        usdc: Token({
          token: IERC20(BaseConfig.USDC),
          priceFeed: IAggregatorV3Interface(BaseConfig.USDC_CHAINLINK_ORACLE)
        }),
        dai: Token({token: IERC20(BaseConfig.DAI), priceFeed: IAggregatorV3Interface(BaseConfig.DAI_CHAINLINK_ORACLE)}),
        rEth: Token({token: IERC20(BaseConfig.rETH), priceFeed: IAggregatorV3Interface(rETH_CHAINLINK_ORACLE)}),
        weth: Token({
          token: IERC20(BaseConfig.WETH),
          priceFeed: IAggregatorV3Interface(BaseConfig.WETH_CHAINLINK_ORACLE)
        })
      })
    )
  {}
}
