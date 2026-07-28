// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IGMTokenManager} from "contracts/interfaces/ondo/IGMTokenManager.sol";
import {IOndoGMSwap} from "contracts/interfaces/ondo/IOndoGMSwap.sol";
import {IOndoAttestationOracle} from "contracts/interfaces/ondo/IOndoAttestationOracle.sol";
import {OndoGMSwapContractGuard} from "contracts/guards/contractGuards/ondo/OndoGMSwapContractGuard.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

abstract contract OndoGMSwapTestSetup is BackboneSetup {
  // --- Ondo addresses ---
  address public constant GOOGLON = 0xbA47214eDd2bb43099611b208f75E4b42FDcfEDc;
  address public constant GM_TOKEN_MANAGER = 0x2c158BC456e027b2AfFCCadF1BDBD9f5fC4c5C8c;
  address internal constant ONDO_IDENTITY_REGISTRY = 0xcf6958D69d535FD03BD6Df3F4fe6CDcd127D97df;
  address internal constant ONDO_IDENTITY_GROUP = 0x428ECB70E90d1527A5f5e177789f51747b883F34;

  // --- Real attestation data from mainnet TXs ---

  // Mint TX (block 24724506): 5,852.93679 USDC -> 19.445568178291830000 GOOGLon
  uint256 internal constant MINT_AMOUNT_IN = 5_852_936_790; // USDC (6 decimals)
  uint256 internal constant MINT_EXPECTED_OUTPUT = 19_445_568_178_291_830_000; // GOOGLon (18 decimals)
  bytes internal constant MINT_ATTESTATION_SIGNATURE =
    hex"dc5dc87b65ae65c48cb0c863e31995b232ae1620fe077103abf0d1afa73d78136f5f9acb26ac854676699a574e5e41f6930306df3e4150f86ce0951ff0fe01051c";

  // Redeem TX (block 24724486): 9.726221784124645000 GOOGLon -> 2,921.142162 USDC
  uint256 internal constant REDEEM_AMOUNT_IN = 9_726_221_784_124_645_000; // GOOGLon (18 decimals)
  uint256 internal constant REDEEM_EXPECTED_OUTPUT = 2_921_142_162; // USDC (6 decimals)
  uint256 internal constant REDEEM_MIN_RECEIVE = 2_921_112_950; // from actual TX minimumReceiveAmount
  bytes internal constant REDEEM_ATTESTATION_SIGNATURE =
    hex"238dda4f8c9cdac7767b593847ec62b98a55c606993fcf04b557229627f38347097d7f30c5a9c15a18e137115465838fc1863e9ae4c14cade2395a5c76f19fc61c";

  // Common
  bytes32 internal constant ONDO_USER_ID = 0x474d0000000000000e88de2c9ee3cae100000000000000000000000000000000;

  // --- Test infrastructure ---
  address public ondoGMSwap; // Deployed behind TransparentUpgradeableProxy
  address public attestationOracle; // OndoAttestationOracle behind proxy
  OndoGMSwapContractGuard public ondoGMSwapGuard;
  PoolLogic public testPool;
  PoolManagerLogic public fundManagerLogic;

  uint256 public constant MAX_SLIPPAGE_BPS = 200; // 2%

  // --- OndoAttestationOracle selectors ---
  bytes4 internal constant INITIALIZE_ORACLE_SELECTOR =
    bytes4(keccak256("initialize(address,address,bytes32,(uint256,uint256,uint256,uint256))"));
  bytes4 internal constant UPDATE_PRICES_SELECTOR =
    bytes4(
      keccak256("updatePrices((uint256,uint256,bytes32,address,uint256,uint256,uint256,uint8,bytes32)[],bytes[])")
    );

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);

    // 1. Register GOOGLon in asset handler with mocked Chainlink aggregator
    address googlonAggregator = makeAddr("googlon_aggregator");
    vm.mockCall(
      googlonAggregator,
      abi.encodeWithSignature("latestRoundData()"),
      abi.encode(uint80(0), int256(300e8), uint256(0), block.timestamp, uint80(0))
    );
    vm.mockCall(googlonAggregator, abi.encodeWithSignature("decimals()"), abi.encode(uint8(8)));
    vm.mockCallRevert(googlonAggregator, abi.encodeWithSignature("oracleHeartbeat()"), "");

    assetHandlerProxy.addAsset(GOOGLON, uint16(AssetTypeIncomplete.CHAINLINK), googlonAggregator);

    // 2. Deploy OndoGMSwap behind proxy (0.8.28 contract, can't import directly)
    address ondoGMSwapImplementation = deployCode("OndoGMSwap.sol:OndoGMSwap");
    ondoGMSwap = address(new TransparentUpgradeableProxy(ondoGMSwapImplementation, proxyAdmin, ""));
    (bool initSuccess, ) = ondoGMSwap.call(
      abi.encodeWithSignature(
        "initialize(address,address,address,address)",
        owner,
        address(poolFactoryProxy),
        GM_TOKEN_MANAGER,
        usdcData.asset
      )
    );
    require(initSuccess, "OndoGMSwap initialize failed");

    // 3. Register OndoGMSwap in Ondo's identity registry so GMTokenManager accepts it
    vm.mockCall(
      ONDO_IDENTITY_REGISTRY,
      abi.encodeWithSignature("getRegisteredID(address,address)", ONDO_IDENTITY_GROUP, ondoGMSwap),
      abi.encode(ONDO_USER_ID)
    );

    // 5. Deploy OndoAttestationOracle behind proxy (0.8.28 contract, cross-version)
    address oracleImpl = deployCode("OndoAttestationOracle.sol:OndoAttestationOracle");
    attestationOracle = address(new TransparentUpgradeableProxy(oracleImpl, proxyAdmin, ""));
    (bool oracleOk, ) = attestationOracle.call(
      abi.encodePacked(
        INITIALIZE_ORACLE_SELECTOR,
        abi.encode(
          owner,
          GM_TOKEN_MANAGER,
          ONDO_USER_ID,
          3600, // maxProofAge
          1000, // sanityDeviationBps (10%)
          1e18, // minQuoteValue
          1_000_000e18 // maxQuoteValue
        )
      )
    );
    require(oracleOk, "OndoAttestationOracle initialize failed");

    // 6. Deploy OndoGMSwapContractGuard (0.7.6, direct import OK)
    ondoGMSwapGuard = new OndoGMSwapContractGuard(
      address(slippageAccumulator),
      MAX_SLIPPAGE_BPS,
      IOndoAttestationOracle(attestationOracle)
    );

    // 7. Register contract guard
    governance.setContractGuard(ondoGMSwap, address(ondoGMSwapGuard));

    vm.stopPrank();

    // 7. Create test pool with USDC + GOOGLon
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: GOOGLON, isDeposit: true});

    vm.startPrank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "OndoTestVault",
        _fundSymbol: "OTV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    fundManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    // 8. Fund pool with USDC deposit
    deal(usdcData.asset, manager, 20_000e6);
    IERC20(usdcData.asset).approve(address(testPool), 20_000e6);
    testPool.deposit(usdcData.asset, 20_000e6);

    // 9. Approve OndoGMSwap to spend pool's tokens
    bytes memory approveUSDC = abi.encodeWithSelector(IERC20.approve.selector, ondoGMSwap, type(uint256).max);
    bytes memory approveGOOGLon = abi.encodeWithSelector(IERC20.approve.selector, ondoGMSwap, type(uint256).max);
    testPool.execTransaction(usdcData.asset, approveUSDC);
    testPool.execTransaction(GOOGLON, approveGOOGLon);
    vm.stopPrank();
  }

  // --- Helper: build mint quote from real TX data ---
  function _getMintQuote() internal pure returns (IGMTokenManager.Quote memory) {
    return
      IGMTokenManager.Quote({
        chainId: 1,
        attestationId: 127426724473290435771477955620127789628,
        userId: ONDO_USER_ID,
        asset: GOOGLON,
        price: 300987772997069065454,
        quantity: 19445568178291830000,
        expiration: 1774320607,
        side: uint8(IGMTokenManager.QuoteSide.BUY),
        additionalData: bytes32(0)
      });
  }

  // --- Helper: build redeem quote from real TX data ---
  function _getRedeemQuote() internal pure returns (IGMTokenManager.Quote memory) {
    return
      IGMTokenManager.Quote({
        chainId: 1,
        attestationId: 37434277619715409041656438775674234140,
        userId: ONDO_USER_ID,
        asset: GOOGLON,
        price: 300336783088357287484,
        quantity: 9726221784124645000,
        expiration: 1774320372,
        side: uint8(IGMTokenManager.QuoteSide.SELL),
        additionalData: bytes32(0)
      });
  }

  // --- Helper: encode swapExactInWithAttestation calldata for mint ---
  function _encodeMintSwapData(uint256 amountIn, uint256 amountOutMinimum) internal view returns (bytes memory) {
    return _encodeMintSwapData(amountIn, amountOutMinimum, _getMintQuote());
  }

  function _encodeMintSwapData(
    uint256 amountIn,
    uint256 amountOutMinimum,
    IGMTokenManager.Quote memory quote
  ) internal view returns (bytes memory) {
    return
      abi.encodeWithSelector(
        IOndoGMSwap.swapExactInWithAttestation.selector,
        usdcData.asset,
        amountIn,
        GOOGLON,
        amountOutMinimum,
        MINT_ATTESTATION_SIGNATURE,
        quote
      );
  }

  // --- Helper: encode swapExactInWithAttestation calldata for redeem ---
  function _encodeRedeemSwapData(uint256 amountIn, uint256 amountOutMinimum) internal view returns (bytes memory) {
    return _encodeRedeemSwapData(amountIn, amountOutMinimum, _getRedeemQuote());
  }

  function _encodeRedeemSwapData(
    uint256 amountIn,
    uint256 amountOutMinimum,
    IGMTokenManager.Quote memory quote
  ) internal view returns (bytes memory) {
    return
      abi.encodeWithSelector(
        IOndoGMSwap.swapExactInWithAttestation.selector,
        GOOGLON,
        amountIn,
        usdcData.asset,
        amountOutMinimum,
        REDEEM_ATTESTATION_SIGNATURE,
        quote
      );
  }

  // --- Helper: mock GM token pause state ---
  function _mockMintingPaused(address _asset, bool paused) internal {
    vm.mockCall(GM_TOKEN_MANAGER, abi.encodeWithSignature("gmTokenMintingPaused(address)", _asset), abi.encode(paused));
  }

  function _mockRedemptionsPaused(address _asset, bool paused) internal {
    vm.mockCall(
      GM_TOKEN_MANAGER,
      abi.encodeWithSignature("gmTokenRedemptionsPaused(address)", _asset),
      abi.encode(paused)
    );
  }
}
