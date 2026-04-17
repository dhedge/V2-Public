// SPDX-License-Identifier: MIT
// solhint-disable contract-name-capwords
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {console} from "forge-std/console.sol";
import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {UniV3TWAPAggregator} from "contracts/priceAggregators/UniV3TWAPAggregator.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";

abstract contract mStableTroubleshootingTest is Test {
  PoolLogic public vault = PoolLogic(EthereumConfig.mPT_sUSDe);
  address public withdrawer = 0xF6FF1F7FCEB2cE6d26687EaaB5988b445d0b94a2;
  address public owner = 0x5a76f841bFe5182f04bf511fC0Ecf88C27189FCB;
  address public assetHandler = 0xBb015300b8D483cc477F027d504Ae580E2F83c72;
  address public existingsUSDeAggregator = 0xD511fbF9618Fa76Dd73796Eb9c3E500030F36A7D;
  IUniswapV3Pool public sUSDeUSDTPool = IUniswapV3Pool(0x7EB59373D63627be64b42406B108B602174B4CCC);
  uint256 public blockNumber;
  uint256 public amount;
  bytes public txData;
  uint32 public twapDurationToUse;

  constructor(uint256 _blockNumber, uint256 _amount, bytes memory _txData, uint32 _twapDuration) {
    blockNumber = _blockNumber;
    amount = _amount;
    txData = _txData;
    twapDurationToUse = _twapDuration;
  }

  function setUp() public virtual {
    vm.createSelectFork("ethereum", blockNumber);
  }

  function test_susde_price_when_oracle_switch() public {
    uint256 priceBefore = AssetHandler(assetHandler).getUSDPrice(EthereumConfig.sUSDe);
    console.log("sUSDe price before oracle switch:", priceBefore);

    _switchOracle();

    uint256 priceAfter = AssetHandler(assetHandler).getUSDPrice(EthereumConfig.sUSDe);
    console.log("sUSDe price after oracle switch:", priceAfter);

    _logDifference(priceBefore, priceAfter);

    UniV3TWAPAggregator twapAggregator = new UniV3TWAPAggregator(
      sUSDeUSDTPool,
      EthereumConfig.sUSDe,
      IAggregatorV3Interface(EthereumConfig.USDT_CHAINLINK_ORACLE),
      twapDurationToUse
    );
    (, int256 twapPrice, , , ) = twapAggregator.latestRoundData();
    console.log("sUSDe TWAP price from Uniswap V3 pool:", uint256(twapPrice) * 1e10);

    _logDifference(priceBefore, uint256(twapPrice) * 1e10);
  }

  function test_token_price_when_oracle_switch() public {
    uint256 tokenPriceBefore = vault.tokenPrice();
    console.log("Token price before oracle switch:", tokenPriceBefore);

    _switchOracle();

    uint256 tokenPriceAfter = vault.tokenPrice();
    console.log("Token price after oracle switch:", tokenPriceAfter);

    _logDifference(tokenPriceBefore, tokenPriceAfter);
  }

  function test_withdrawal_value_if_oracle_switched() public {
    vm.skip(amount == 0);

    _switchOracle();

    uint256 withdrawalValue = vault.tokenPrice() * amount;
    console.log("Withdrawal value after oracle switch:", withdrawalValue);
  }

  function test_withdraw_tokens() public {
    vm.skip(amount == 0 || txData.length == 0);

    uint256 tokenPriceBefore = vault.tokenPrice();
    uint256 withdrawalValue = tokenPriceBefore * amount;
    console.log("Withdrawal value:", withdrawalValue);

    vm.prank(withdrawer);
    (bool success, ) = address(vault).call(txData); // Transaction data is taken from simulation - 1M vault tokens: https://dashboard.tenderly.co/public/safe/safe-apps/simulator/836681d5-fcea-4064-800c-b230c1a0a56f
    require(success, "Withdrawal failed");

    address poolManagerLogic = vault.poolManagerLogic();
    uint256 valueReceived = PoolManagerLogic(poolManagerLogic).assetValue(
      EthereumConfig.sUSDe,
      PoolLogic(EthereumConfig.sUSDe).balanceOf(withdrawer)
    ) +
      PoolManagerLogic(poolManagerLogic).assetValue(
        EthereumConfig.USDT,
        PoolLogic(EthereumConfig.USDT).balanceOf(withdrawer)
      ) +
      PoolManagerLogic(poolManagerLogic).assetValue(
        EthereumConfig.PT_sUSDe_NOV_2025,
        PoolLogic(EthereumConfig.PT_sUSDe_NOV_2025).balanceOf(withdrawer)
      );
    console.log("Value received after withdrawal:", valueReceived);
  }

  /// @dev Just switches to sUSDe Chainlink
  function _switchOracle() internal virtual {
    vm.prank(owner);
    AssetHandler(assetHandler).addAsset(EthereumConfig.sUSDe, 200, EthereumConfig.sUSDe_CHAINLINK_ORACLE);

    // The on-chain deployed PT aggregator still uses the old UnderlyingAssetOracleUpdater with stored state,
    // so we need to call updateUnderlyingAggregator() to refresh its cached reference after the oracle switch.
    (bool success, ) = EthereumConfig.PT_sUSDe_NOV_2025_PRICE_AGGREGATOR.call(
      abi.encodeWithSignature("updateUnderlyingAggregator()")
    );
    require(success, "updateUnderlyingAggregator failed");
  }

  function _logDifference(uint256 _before, uint256 _after) internal pure {
    if (_before == 0) {
      console.log("Changed from 0 to:");
      console.log(_after);
      return;
    }

    uint256 difference = _before > _after ? _before - _after : _after - _before;

    // Calculate percentage difference with 2 decimal precision
    uint256 percentageBasisPoints = (difference * 10000) / _before;
    uint256 wholePercent = percentageBasisPoints / 100;
    uint256 decimalPercent = percentageBasisPoints % 100;

    string memory direction = _after > _before ? "Increased" : "Decreased";

    console.log(direction);
    console.log("Percentage change in basis points:", percentageBasisPoints);
    console.log("Whole percent:", wholePercent);
    console.log("Decimal part:", decimalPercent);
  }
}
