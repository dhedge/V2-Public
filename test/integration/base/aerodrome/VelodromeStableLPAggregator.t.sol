// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;
// solhint-disable no-console

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IVelodromeV2Pair} from "../../../../contracts/interfaces/velodrome/IVelodromeV2Pair.sol";
import {IAssetHandler} from "../../../../contracts/interfaces/IAssetHandler.sol";
import {IAggregatorV3Interface} from "../../../../contracts/interfaces/IAggregatorV3Interface.sol";
import {VelodromeStableLPAggregator} from "../../../../contracts/priceAggregators/VelodromeStableLPAggregator.sol";
import {VelodromeV2TWAPAggregator} from "../../../../contracts/priceAggregators/VelodromeV2TWAPAggregator.sol";

contract VelodromeStableLPAggregatorTest is Test {
  string public baseRpcUrl = vm.envString("BASE_URL");

  address public dHEDGEAdminBase = 0x4A83129Ce9C8865EF3f91Fc87130dA25b64F9100;

  IAssetHandler public assetHandlerProxy = IAssetHandler(0x559082da2Be5b23bF4339Fd610Cd4404Fe5f8013);

  IVelodromeV2Pair public wethAndRethStableLP = IVelodromeV2Pair(0xb8866732424AcDdd729C6fcf7146b19bFE4A2e36);

  VelodromeStableLPAggregator public wethAndRethVelodromeStableLPAggregator =
    VelodromeStableLPAggregator(0x1Ed669eF159C3Ae43A4f7dC3D1A555827E0aCbfc);
  IAggregatorV3Interface public token0ChainlinkOracleAddress =
    IAggregatorV3Interface(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70); // WETH
  IAggregatorV3Interface public token1ChainlinkOracleAddress =
    IAggregatorV3Interface(0xbe1551fB22F8b877EDF3731CEc6FF703E720Fb85); // rETH

  function setUp() public {
    vm.createSelectFork(baseRpcUrl);
  }

  function test_inflated_lp_price() public {
    (, int256 currentLPPrice, , , ) = wethAndRethVelodromeStableLPAggregator.latestRoundData();
    console.log("currentLPPrice:", currentLPPrice);

    int256 actualLPPrice = _calculateLPPrice();
    console.log("actualLPPrice", actualLPPrice);

    _setTWAPOracleForrETH();

    (, int256 newLPPrice, , , ) = wethAndRethVelodromeStableLPAggregator.latestRoundData();
    console.log("newLPPrice", newLPPrice);
  }

  function _calculateLPPrice() internal view returns (int256 lpPrice) {
    (uint256 token0Amount, uint256 token1Amount, ) = wethAndRethStableLP.getReserves();
    uint256 totalSupply = wethAndRethStableLP.totalSupply();

    (, int256 token0Price, , , ) = token0ChainlinkOracleAddress.latestRoundData();
    (, int256 token1Price, , , ) = token1ChainlinkOracleAddress.latestRoundData();

    lpPrice = ((token0Price * int256(token0Amount)) + (token1Price * int256(token1Amount))) / int256(totalSupply);
  }

  function _setTWAPOracleForrETH() internal {
    VelodromeV2TWAPAggregator twapOracle = _deployTWAPrETHOracle();

    address token1 = wethAndRethStableLP.token1(); // rETH

    vm.prank(dHEDGEAdminBase);
    assetHandlerProxy.addAsset(token1, 22, address(twapOracle));
  }

  function _deployTWAPrETHOracle() internal returns (VelodromeV2TWAPAggregator twapOracle) {
    address token0 = wethAndRethStableLP.token0(); // WETH
    address token1 = wethAndRethStableLP.token1(); // rETH

    twapOracle = new VelodromeV2TWAPAggregator(
      address(wethAndRethStableLP),
      token1,
      token0,
      token0ChainlinkOracleAddress
    );
  }
}
