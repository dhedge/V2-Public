// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IPyth} from "contracts/interfaces/pyth/IPyth.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

abstract contract OndoPythPriceAggregatorTestSetup is BackboneSetup {
  // --- Real mainnet contracts ---
  address public constant PYTH_CONTRACT = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
  address public constant GM_TOKEN_MANAGER = 0x2c158BC456e027b2AfFCCadF1BDBD9f5fC4c5C8c;
  address public constant SVALUE_ORACLE = 0x9BC39DB6fbB44B91a48b8D5A6C208B82B1741bE6;
  address public constant NVDA_ON = 0x2D1F7226Bd1F780AF6B9A49DCC0aE00E8Df4bDEE;

  // --- NVDA Pyth price feed IDs ---
  bytes32 internal constant NVDA = 0xb1073854ed24cbc755dc527418f52b7d271f6cc967bbf8d8129112b18860a593;
  bytes32 internal constant NVDA_OVERNIGHT = 0xc949a96fd1626e82abc5e1496e6e8d44683ac8ac288015ee90bf37257e3e6bf6;
  bytes32 internal constant NVDA_POST_MARKET = 0x25719379353a508b1531945f3c466759d6efd866f52fbaeb3631decb70ba381f;
  bytes32 internal constant NVDA_PRE_MARKET = 0x61c4ca5b9731a79e285a01e24432d57d89f0ecdd4cd7828196ca8992d5eafef6;

  // --- Config ---
  uint32 internal constant ONCHAIN_MAX_AGE = 172800; // 48h, matches the sanity oracle's maxTimeDelay
  uint32 internal constant PYTH_MAX_AGE = 86400;
  uint32 internal constant PYTH_MIN_CONFIDENCE_RATIO = 50;

  // --- NVDA_PRE_MARKET Pyth update data (fetched from Hermes at block 24820850) ---
  // Price: $177.63304 (price=17763304, expo=-5), conf=5303, publishTime=1775481129
  uint256 internal constant NVDA_PRE_MARKET_PUBLISH_TIME = 1775481129;
  uint256 internal constant NVDA_PRE_MARKET_PRICE_18DEC = 177_633_040_000_000_000_000; // 17763304 * 1e13

  // --- Deployed aggregator ---
  address public aggregator;

  function setUp() public virtual override {
    super.setUp();

    // Deploy aggregator with ALL real mainnet contracts
    bytes32[] memory priceIds = new bytes32[](4);
    priceIds[0] = NVDA;
    priceIds[1] = NVDA_OVERNIGHT;
    priceIds[2] = NVDA_POST_MARKET;
    priceIds[3] = NVDA_PRE_MARKET;

    aggregator = deployCode(
      "OndoPythPriceAggregator.sol:OndoPythPriceAggregator",
      abi.encode(
        PYTH_CONTRACT,
        GM_TOKEN_MANAGER,
        SVALUE_ORACLE,
        NVDA_ON,
        priceIds,
        ONCHAIN_MAX_AGE,
        PYTH_MAX_AGE,
        PYTH_MIN_CONFIDENCE_RATIO
      )
    );

    // Push frozen NVDA_PRE_MARKET price data to the real Pyth contract
    _pushPythUpdateData();

    // Default to sValue = 1e18 (no-op multiplier). Tests exercising sValue override this.
    // Required because _applySValue reverts on oracle revert or zero sValue.
    _mockSValue(uint128(1e18), false);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Frozen Pyth update data
  // ═══════════════════════════════════════════════════════════════════════

  function _getPythUpdateData() internal pure returns (bytes memory) {
    return
      hex"504e41550100000003b801000000050d0036092eeb1fbaebea8f8651be743db4e5a60091938c662fb9604769117d273c33396a88964952845c93a6e95ec83f9bc9a744c47d089f4c8ec90dd32a5763dff8010150cc389b8d910aae5025a9c2acb8c422cadd9b0ee73d01a342db1e116d8e049c5eb3932ec49c6f80a625cbcc716bb49f9c554dfe896d6a6955e14d9977323be70002c7e3074af30b5782cb8ac483fabb3db4934eb059ae3d05f5a43a1cc7bafa015a7937af923177c51c92c895afb764740400f67bd13db99bb477ca09ab3dee76570003193ae2443c1234449bd3bf1eadddf5ccadef29dc6b4e41ca972f301462f913bf68f50e534ce46fa9691690c53f0f147ca7ea9d826f6f0487ecc87634c0cb2b0b0104706160dfa62032b90ce82295347006611279682eebdaff09f7feee717215071c59344dbc35ed104128f51acbcab9b378dade1b6a18dbee8e8e3be96666e8e4f90106fcfb585787c2259a1752de828d780a71c4ed602e4c6c295ca82b2c7c683e0fdd1d0306eb9a85e3a693b6499d773ab68caa49db805ad6b2d9daffd0879a8bdaec010997cb1f94927d2e41f8841f077829d53cef8fa100a7a048995a7fbe99fc16367e4d696516024a47acca9bce6c9110dc96798e9bb7000f8b81d81c0ba7d6c9d433000b7204b442d16cb60e00fdc8357182404e4fcea7adfebaf0c53dce03f2c266ec9965574d3d40a284af55d061a75165655d13cbb0353891974dbcb83bf18c2b2298000c196450889a55e67925b89d82cba6414803a1132582f1f89cbf033f8bd971d36b6507fa1f66442c1b4e981c163baa509bf81a45bf190fa6b32a67ed3ba8e958f2010dd38f0380d7d0c863a000d7b80a42393d107e20bc217b9dbc6d0f3177a28ea67853cbf6d4f1642c808c00e3912e0ac1545583811e54a6b4c2d10f615a62743e80000e144f85b38af9381c88747a70616511556ada4694bad540ea3c1345ebe5fc745014eb7579d301d00efb06ace265e71b6c332592d82c2190a41b1231dbd9128e43000f965a40c12b0e23081f46bc6ee97a6aaf064824e053cc5bafac3f95172f07bd1e7311db02ca9ad52139ecc3973561ffd527b84cc137254fd27990558396fbf42b0012238e95645f188aaf14036f4221428e97525c3263540c05b99ae7abb4fc20a1332a4e938cc40819087230dfc3dfcb0373f5162b73073330d236578615d29f33aa0069d3b12900000000001ae101faedac5851e32b9b23b5f9411a8c2bac4aae3ed4dd7b811dd1a72ea4aa71000000000bd3fc4a0141555756000000000010e1a6820000271045a61367737fcc46a04484936fb2726d6058f5180100550061c4ca5b9731a79e285a01e24432d57d89f0ecdd4cd7828196ca8992d5eafef600000000010f0be800000000000014b7fffffffb0000000069d3b1290000000069d3b12800000000010f7e6100000000000019f20d96e8681a7f6472d49e3ca63f05e86343d979f2039a99e1050b5f6fd5e7d3b49e3dad3654a421f57e3f366fe5efcf791bdbf1f74268276bb999ce07d28a770486b3a0aebeca86c31967128e899adf62bcb7f87618b95bf6e348dce87f33f14bcc14e46a2b5a0cb088f2998b156bf3e1913ac11917aee2f75b287ee6d9181bf0f5244b1ad3549e6b098a8e79e25f441789caadb1145ce827840ad5cbf4d1d37d45309ebe02360e2389aa7f70f8ca0ef8bcba57c4251d349e19e21aa1471bccf2817584f937627406671a019d4771c084848babb0630d214c21c9b2a08559616cf1a56d82f40de03a461cab94ded6d76d747fded9b59c276c49214cca74994c0119e99ae805";
  }

  function _pushPythUpdateData() internal {
    bytes[] memory updateArr = new bytes[](1);
    updateArr[0] = _getPythUpdateData();
    uint256 fee = IPyth(PYTH_CONTRACT).getUpdateFee(updateArr);
    vm.deal(address(this), fee);
    IPyth(PYTH_CONTRACT).updatePriceFeeds{value: fee}(updateArr);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Mock helpers (for edge-case tests that need to override real oracles)
  // ═══════════════════════════════════════════════════════════════════════

  function _mockOnchainPrice(uint256 price, uint64 lastUpdated, uint16 deviationBps) internal {
    address realSanityOracle = _getSanityCheckOracle();
    vm.mockCall(
      realSanityOracle,
      abi.encodeWithSignature("prices(address)", NVDA_ON),
      abi.encode(price, lastUpdated, uint32(0), deviationBps)
    );
  }

  function _mockSValue(uint128 sValue, bool paused) internal {
    vm.mockCall(SVALUE_ORACLE, abi.encodeWithSignature("getSValue(address)", NVDA_ON), abi.encode(sValue, paused));
  }

  function _mockSValueRevert() internal {
    vm.mockCallRevert(
      SVALUE_ORACLE,
      abi.encodeWithSignature("getSValue(address)", NVDA_ON),
      abi.encodePacked("AssetNotFound")
    );
  }

  function _mockPythPriceRevert(bytes32 priceId) internal {
    vm.mockCallRevert(
      PYTH_CONTRACT,
      abi.encodeWithSignature("getPriceNoOlderThan(bytes32,uint256)", priceId, uint256(PYTH_MAX_AGE)),
      abi.encodePacked("stale price")
    );
  }

  function _mockPythPrice(bytes32 priceId, int64 price, uint64 conf, int32 expo, uint256 pubTime) internal {
    vm.mockCall(
      PYTH_CONTRACT,
      abi.encodeWithSignature("getPriceNoOlderThan(bytes32,uint256)", priceId, uint256(PYTH_MAX_AGE)),
      abi.encode(price, conf, expo, pubTime)
    );
  }

  function _mockAllPythFeedsRevert() internal {
    _mockPythPriceRevert(NVDA);
    _mockPythPriceRevert(NVDA_OVERNIGHT);
    _mockPythPriceRevert(NVDA_POST_MARKET);
    _mockPythPriceRevert(NVDA_PRE_MARKET);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Call helpers
  // ═══════════════════════════════════════════════════════════════════════

  function _getSanityCheckOracle() internal returns (address) {
    (bool success, bytes memory data) = GM_TOKEN_MANAGER.call(abi.encodeWithSignature("sanityCheckOracle()"));
    require(success, "sanityCheckOracle() failed");
    return abi.decode(data, (address));
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

  function _mockMintingPaused(bool paused) internal {
    vm.mockCall(
      GM_TOKEN_MANAGER,
      abi.encodeWithSignature("gmTokenMintingPaused(address)", NVDA_ON),
      abi.encode(paused)
    );
  }

  function _mockRedemptionsPaused(bool paused) internal {
    vm.mockCall(
      GM_TOKEN_MANAGER,
      abi.encodeWithSignature("gmTokenRedemptionsPaused(address)", NVDA_ON),
      abi.encode(paused)
    );
  }
}
