//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {IPoolLogic} from "../interfaces/IPoolLogic.sol";

contract DHedgePoolAggregator is IAggregatorV3Interface {
  IPoolLogic public immutable poolLogic;

  constructor(address _poolLogic) {
    require(_poolLogic != address(0), "invalid address");
    poolLogic = IPoolLogic(_poolLogic);
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
    uint256 tokenPrice = poolLogic.tokenPrice();
    // adjust decimals -> 8
    return (0, int256(tokenPrice / 1e10), 0, block.timestamp, 0);
  }
}
