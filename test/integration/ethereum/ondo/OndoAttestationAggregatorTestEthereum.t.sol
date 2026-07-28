// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IGMTokenManager} from "contracts/interfaces/ondo/IGMTokenManager.sol";
import {OndoAttestationOracleTestSetup} from "test/integration/common/ondo/OndoAttestationOracleTestSetup.t.sol";
import {AssetTypes} from "test/integration/utils/foundry/AssetTypes.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";

contract OndoAttestationAggregatorTestEthereum is OndoAttestationOracleTestSetup, EthereumSetup {
  address public aggregator;

  constructor() EthereumSetup(24875501) OndoAttestationOracleTestSetup() {}

  function setUp() public override(OndoAttestationOracleTestSetup, EthereumSetup) {
    EthereumSetup.setUp();
    OndoAttestationOracleTestSetup.setUp();
    _storeDefaultPrice();
    aggregator = deployCode(
      "OndoAttestationAggregator.sol:OndoAttestationAggregator",
      abi.encode(attestationOracle, NFLX_ON)
    );
  }

  function _getDecimals() internal view returns (uint8) {
    return IAggregatorV3Interface(aggregator).decimals();
  }

  function _getLatestRoundData()
    internal
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    return IAggregatorV3Interface(aggregator).latestRoundData();
  }

  function test_constructor_setsImmutables() public view {
    (bool s1, bytes memory d1) = aggregator.staticcall(abi.encodeWithSignature("oracle()"));
    require(s1);
    assertEq(abi.decode(d1, (address)), attestationOracle);

    (bool s2, bytes memory d2) = aggregator.staticcall(abi.encodeWithSignature("ondoAsset()"));
    require(s2);
    assertEq(abi.decode(d2, (address)), NFLX_ON);
  }

  function test_revert_constructor_zeroOracle() public {
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroAddress(string)")), "_oracle"));
    deployCode("OndoAttestationAggregator.sol:OndoAttestationAggregator", abi.encode(address(0), NFLX_ON));
  }

  function test_revert_constructor_zeroOndoAsset() public {
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroAddress(string)")), "_ondoAsset"));
    deployCode("OndoAttestationAggregator.sol:OndoAttestationAggregator", abi.encode(attestationOracle, address(0)));
  }

  function test_decimals_returns8() public view {
    assertEq(uint256(_getDecimals()), uint256(8));
  }

  function test_oracleHeartbeat_returns49Hours() public view {
    (bool success, bytes memory data) = aggregator.staticcall(abi.encodeWithSignature("oracleHeartbeat()"));
    require(success);
    assertEq(abi.decode(data, (uint256)), 49 hours);
  }

  function test_latestRoundData_returnsValidPrice() public view {
    (, int256 answer, , uint256 updatedAt, ) = _getLatestRoundData();
    assertGt(answer, 0, "price should be positive");
    assertGt(updatedAt, 0, "updatedAt should be non-zero");
  }

  function test_latestRoundData_converts18DecTo8Dec() public {
    _mockSanityOracleRevert(NFLX_ON);
    IGMTokenManager.Quote memory quote = _buildQuote(123_456_789_012_345_678_901, 1e18, block.timestamp + 10);
    _updateSinglePrice(quote, _signQuote(quote));
    (, int256 answer, , , ) = _getLatestRoundData();
    assertEq(answer, int256(uint256(123_456_789_012_345_678_901) / 1e10));
  }

  function test_latestRoundData_returnsChainlinkFormat() public view {
    (uint80 roundId, , uint256 startedAt, , uint80 answeredInRound) = _getLatestRoundData();
    assertEq(uint256(roundId), 0);
    assertEq(startedAt, 0);
    assertEq(uint256(answeredInRound), 0);
  }

  function test_latestRoundData_updatedAtMatchesOracle() public view {
    (, , , uint256 updatedAt, ) = _getLatestRoundData();
    assertEq(updatedAt, block.timestamp);
  }

  function test_revert_latestRoundData_mintingPaused() public {
    _mockMintingPaused(NFLX_ON, true);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OndoMintingPaused()"))));
    _getLatestRoundData();
  }

  function test_revert_latestRoundData_redemptionsPaused() public {
    _mockRedemptionsPaused(NFLX_ON, true);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OndoRedemptionsPaused()"))));
    _getLatestRoundData();
  }

  function test_latestRoundData_usesAttestedPrice() public {
    _mockSanityOracleRevert(NFLX_ON);
    (, int256 answer, , , ) = _getLatestRoundData();
    assertEq(answer, int256(1030e8));
  }

  function test_latestRoundData_usesSanityPrice_whenFresher() public {
    vm.warp(block.timestamp + 200);
    _mockSanityOraclePrice(NFLX_ON, 1050e18, uint64(block.timestamp), 172800, 0);
    (, int256 answer, , , ) = _getLatestRoundData();
    assertEq(answer, int256(1050e8));
  }

  function test_revert_latestRoundData_noPriceAvailable() public {
    vm.warp(block.timestamp + MAX_PROOF_AGE + 1);
    _mockSanityOracleRevert(NFLX_ON);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("NoPriceAvailable()"))));
    _getLatestRoundData();
  }

  function test_assetHandler_returnsPrice_whenSanityPriceWithin49h() public {
    vm.startPrank(owner);
    assetHandlerProxy.setChainlinkTimeout(90000); // 25h production value
    assetHandlerProxy.addAsset(NFLX_ON, uint16(AssetTypes.AssetTypeIncomplete.CHAINLINK), aggregator);
    vm.stopPrank();

    // Warp 26h so the attested price (set in setUp) becomes invalid (>1h MAX_PROOF_AGE).
    // Sanity oracle is mocked to be 26h stale but valid from Ondo's POV (maxTimeDelay 48h).
    // 26h < 49h heartbeat, so AssetHandler should accept.
    vm.warp(block.timestamp + 26 hours);
    _mockSanityOraclePrice(NFLX_ON, 1030e18, uint64(block.timestamp - 26 hours), uint32(48 hours), 0);

    uint256 price = assetHandlerProxy.getUSDPrice(NFLX_ON);
    assertEq(price, 1030e18);
  }

  function test_revert_assetHandler_whenSanityPriceOlderThan49h() public {
    vm.startPrank(owner);
    assetHandlerProxy.setChainlinkTimeout(90000); // 25h production value
    assetHandlerProxy.addAsset(NFLX_ON, uint16(AssetTypes.AssetTypeIncomplete.CHAINLINK), aggregator);
    vm.stopPrank();

    // Sanity oracle is 50h stale but still valid from Ondo's POV (maxTimeDelay 100h).
    // 50h > 49h heartbeat, so AssetHandler should reject.
    vm.warp(block.timestamp + 50 hours);
    _mockSanityOraclePrice(NFLX_ON, 1030e18, uint64(block.timestamp - 50 hours), uint32(100 hours), 0);

    vm.expectRevert("Chainlink price expired");
    assetHandlerProxy.getUSDPrice(NFLX_ON);
  }
}
