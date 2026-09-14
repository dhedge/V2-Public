// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";

/// @notice `AssetHandler` is the registry mapping an asset to its type and price feed, and the
/// single place USD prices are read from. Everything that mutates it is owner-only, and every way
/// a price can be untrustworthy has to surface as a revert rather than a bad number.
contract AssetHandlerTest is Test {
  uint256 internal constant CHAINLINK_TIMEOUT = 90_000;
  int256 internal constant ONE_DOLLAR = 1e8; // Chainlink feeds carry 8 decimals

  AssetHandler internal assetHandler;

  address internal notOwner = makeAddr("notOwner");
  address internal assetA = makeAddr("assetA");
  address internal assetB = makeAddr("assetB");
  address internal unregisteredAsset = makeAddr("unregisteredAsset");
  address internal feedA = makeAddr("feedA");
  address internal feedB = makeAddr("feedB");

  function setUp() public {
    // Start well past the epoch so a feed can report a timestamp in the past.
    vm.warp(365 days);

    _mockFeed(feedA, ONE_DOLLAR, block.timestamp);
    _mockFeed(feedB, ONE_DOLLAR, block.timestamp);

    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({asset: assetA, assetType: 1, aggregator: feedA});

    assetHandler = new AssetHandler();
    assetHandler.initialize(assets);
    assetHandler.setChainlinkTimeout(CHAINLINK_TIMEOUT);
  }

  /* ========== REGISTRY ACCESS CONTROL ========== */

  function test_revert_addAsset_when_not_owner() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    assetHandler.addAsset(assetB, 0, feedB);
  }

  function test_revert_addAssets_when_not_owner() public {
    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({asset: assetB, assetType: 0, aggregator: feedB});

    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    assetHandler.addAssets(assets);
  }

  function test_revert_removeAsset_when_not_owner() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    assetHandler.removeAsset(assetA);
  }

  function test_revert_setChainlinkTimeout_when_not_owner() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    assetHandler.setChainlinkTimeout(90);
  }

  /* ========== REGISTRY CONTENTS ========== */

  function test_initialized_asset_is_registered() public view {
    assertEq(uint256(assetHandler.assetTypes(assetA)), 1);
    assertEq(assetHandler.priceAggregators(assetA), feedA);
  }

  function test_unknown_asset_reads_as_empty() public view {
    assertEq(uint256(assetHandler.assetTypes(unregisteredAsset)), 0);
    assertEq(assetHandler.priceAggregators(unregisteredAsset), address(0));
  }

  function test_owner_can_add_a_single_asset() public {
    assetHandler.addAsset(assetB, 4, feedB);

    assertEq(uint256(assetHandler.assetTypes(assetB)), 4);
    assertEq(assetHandler.priceAggregators(assetB), feedB);
  }

  function test_owner_can_add_assets_in_bulk() public {
    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](2);
    assets[0] = IAssetHandler.Asset({asset: assetA, assetType: 7, aggregator: feedA});
    assets[1] = IAssetHandler.Asset({asset: assetB, assetType: 8, aggregator: feedB});

    assetHandler.addAssets(assets);

    // Re-adding an existing asset overwrites its type.
    assertEq(uint256(assetHandler.assetTypes(assetA)), 7);
    assertEq(uint256(assetHandler.assetTypes(assetB)), 8);
  }

  function test_owner_can_remove_an_asset() public {
    assetHandler.removeAsset(assetA);

    assertEq(uint256(assetHandler.assetTypes(assetA)), 0);
    assertEq(assetHandler.priceAggregators(assetA), address(0));
  }

  function test_revert_adding_an_asset_without_a_feed() public {
    vm.expectRevert("aggregator address cannot be 0");
    assetHandler.addAsset(assetB, 1, address(0));
  }

  function test_owner_can_change_the_chainlink_timeout() public {
    assetHandler.setChainlinkTimeout(90);

    assertEq(assetHandler.chainlinkTimeout(), 90);
  }

  /* ========== PRICING ========== */

  function test_price_is_scaled_to_eighteen_decimals() public view {
    assertEq(assetHandler.getUSDPrice(assetA), 1e18);
  }

  function test_revert_pricing_an_unregistered_asset() public {
    vm.expectRevert("Price aggregator not found");
    assetHandler.getUSDPrice(unregisteredAsset);
  }

  function test_revert_pricing_an_asset_after_it_is_removed() public {
    assetHandler.removeAsset(assetA);

    vm.expectRevert("Price aggregator not found");
    assetHandler.getUSDPrice(assetA);
  }

  function test_revert_when_the_feed_reverts() public {
    vm.mockCallRevert(feedA, abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector), "");

    vm.expectRevert("Price get failed");
    assetHandler.getUSDPrice(assetA);
  }

  function test_revert_when_the_feed_answer_is_stale() public {
    _mockFeed(feedA, ONE_DOLLAR, block.timestamp - CHAINLINK_TIMEOUT - 1);

    vm.expectRevert("Chainlink price expired");
    assetHandler.getUSDPrice(assetA);
  }

  /// @dev Feeds that update slowly (Ondo's ~2 day attestation oracle, say) may advertise their own
  /// heartbeat, which is honoured in place of the global timeout.
  function test_feed_advertising_a_longer_heartbeat_is_still_accepted_when_past_the_global_timeout() public {
    _mockFeed(feedA, ONE_DOLLAR, block.timestamp - CHAINLINK_TIMEOUT - 1);
    vm.mockCall(feedA, abi.encodeWithSignature("oracleHeartbeat()"), abi.encode(uint256(7 days)));

    assertEq(assetHandler.getUSDPrice(assetA), 1e18);
  }

  function test_revert_when_a_feed_is_stale_even_by_its_own_heartbeat() public {
    _mockFeed(feedA, ONE_DOLLAR, block.timestamp - 8 days);
    vm.mockCall(feedA, abi.encodeWithSignature("oracleHeartbeat()"), abi.encode(uint256(7 days)));

    vm.expectRevert("Chainlink price expired");
    assetHandler.getUSDPrice(assetA);
  }

  function test_revert_when_the_feed_reports_no_price() public {
    _mockFeed(feedA, 0, block.timestamp);

    vm.expectRevert("Price not available");
    assetHandler.getUSDPrice(assetA);
  }

  function test_revert_when_the_feed_reports_a_negative_price() public {
    _mockFeed(feedA, -1, block.timestamp);

    vm.expectRevert("Price not available");
    assetHandler.getUSDPrice(assetA);
  }

  /// @dev Models an ordinary Chainlink feed: it answers `latestRoundData` and does not implement
  /// the optional `oracleHeartbeat` extension, so probing for one reverts.
  function _mockFeed(address _feed, int256 _answer, uint256 _updatedAt) internal {
    vm.mockCall(
      _feed,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(uint80(0), _answer, uint256(0), _updatedAt, uint80(0))
    );
    vm.mockCallRevert(_feed, abi.encodeWithSignature("oracleHeartbeat()"), "");
  }
}
