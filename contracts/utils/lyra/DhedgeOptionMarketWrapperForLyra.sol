// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../../guards/contractGuards/LyraOptionMarketWrapperContractGuard.sol";
import "../../interfaces/aave/v2/ILendingPool.sol";
import "../../interfaces/lyra/ILyraRegistry.sol";
import "../../interfaces/lyra/IOptionMarketViewer.sol";
import "../../interfaces/lyra/IOptionMarketWrapper.sol";
import "../../interfaces/lyra/IOptionToken.sol";
import "../../interfaces/lyra/ISynthetixAdapter.sol";
import "../../interfaces/lyra/IGWAVOracle.sol";
import "../../interfaces/synthetix/ISynthetix.sol";
import "../../interfaces/synthetix/IExchanger.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IHasGuardInfo.sol";

contract DhedgeOptionMarketWrapperForLyra {
  using SafeMath for uint256;

  bytes32 public constant MARKET_VIEWER = "MARKET_VIEWER";
  bytes32 public constant MARKET_WRAPPER = "MARKET_WRAPPER";
  bytes32 public constant SYNTHETIX_ADAPTER = "SYNTHETIX_ADAPTER";

  ILyraRegistry public immutable lyraRegistry;
  ILendingPool public immutable aaveLendingPool;

  constructor(ILyraRegistry _lyraRegistry, address _aaveLendingPool) {
    lyraRegistry = _lyraRegistry;
    aaveLendingPool = ILendingPool(_aaveLendingPool);
  }

  function getOptionMarketViewer() public view returns (IOptionMarketViewer) {
    return IOptionMarketViewer(lyraRegistry.getGlobalAddress(MARKET_VIEWER));
  }

  function getOptionMarketWrapper() public view returns (IOptionMarketWrapper) {
    return IOptionMarketWrapper(lyraRegistry.getGlobalAddress(MARKET_WRAPPER));
  }

  function getSynthetixAdapter() public view returns (ISynthetixAdapter) {
    return ISynthetixAdapter(lyraRegistry.getGlobalAddress(SYNTHETIX_ADAPTER));
  }

  function _encodeCloseParams(
    IOptionMarketViewer.OptionMarketAddresses memory optionMarketAddresses,
    IOptionToken.OptionPosition memory position,
    uint256 portion
  ) internal pure returns (IOptionMarketWrapper.OptionPositionParams memory params) {
    return
      IOptionMarketWrapper.OptionPositionParams({
        optionMarket: IOptionMarket(optionMarketAddresses.optionMarket),
        strikeId: position.strikeId,
        positionId: position.positionId,
        iterations: 1,
        currentCollateral: position.collateral,
        setCollateralTo: position.collateral.sub(position.collateral.mul(portion).div(10**18)),
        optionType: position.optionType,
        amount: position.amount.mul(portion).div(10**18),
        minCost: 0,
        maxCost: type(uint256).max,
        inputAmount: 0,
        inputAsset: IERC20(optionMarketAddresses.quoteAsset)
      });
  }

  /// @notice This function is to close lyra option position - called from PoolLogic contract
  /// @dev the original Lyra close/forceClose position functions doesn't accept recipient address
  ///      this function will accept a recipient address and withdraw the funds to the recipient directly.
  /// @param dhedgeStoredPosition the position information dhedge stores
  /// @param portion the portion of the withdrawer
  /// @param recipient the recipient address for withdrawn funds
  function tryCloseAndForceClosePosition(
    LyraOptionMarketWrapperContractGuard.OptionPosition memory dhedgeStoredPosition,
    uint256 portion,
    address recipient
  ) external {
    IOptionMarketViewer.OptionMarketAddresses memory optionMarketAddresses = getOptionMarketViewer().marketAddresses(
      address(dhedgeStoredPosition.optionMarket)
    );
    IOptionToken.OptionPosition memory position = optionMarketAddresses.optionToken.positions(
      dhedgeStoredPosition.positionId
    );

    IOptionMarketWrapper.OptionPositionParams memory closeParams = _encodeCloseParams(
      optionMarketAddresses,
      position,
      portion
    );

    if (
      closeParams.optionType == IOptionMarket.OptionType.SHORT_CALL_BASE ||
      closeParams.optionType == IOptionMarket.OptionType.SHORT_CALL_QUOTE ||
      closeParams.optionType == IOptionMarket.OptionType.SHORT_PUT_QUOTE
    ) {
      // check minimum collateral amount after withdraw
      (uint256 strikePrice, uint256 expiry) = closeParams.optionMarket.getStrikeAndExpiry(position.strikeId);
      uint256 spotPrice = getSynthetixAdapter().getSpotPriceForMarket(address(closeParams.optionMarket));
      uint256 minCollateralAfterWithdraw = optionMarketAddresses.greekCache.getMinCollateral(
        closeParams.optionType,
        strikePrice,
        expiry,
        spotPrice,
        position.amount.sub(closeParams.amount)
      );

      // check if the position collateral is less than the minimum collateral amount
      // then it will close position fully and withdraw to the pool address directly
      if (closeParams.setCollateralTo < minCollateralAfterWithdraw) {
        closeParams.setCollateralTo = 0;
        closeParams.amount = position.amount;
        recipient = msg.sender;
      }
    }

    IOptionMarketWrapper optionMarketWrapper = getOptionMarketWrapper();

    optionMarketAddresses.optionToken.approve(address(optionMarketWrapper), closeParams.positionId);
    if (closeParams.optionType == IOptionMarket.OptionType.SHORT_CALL_BASE) {
      // to close SHORT_CALL_BASE options, it requires to provide option fees in quote asset.
      // 1. we flashloan quote asset from Aave
      // 2. close option position
      // 3. we get base asset once we close the option position.
      // 4. we swap base asset into quote asset to repay flahsloan amount + premium

      uint256 amountToFlashloan = getAmountOfQuoteToBorrow(closeParams);

      address[] memory borrowAssets = new address[](1);
      borrowAssets[0] = address(optionMarketAddresses.quoteAsset);
      uint256[] memory borrowAmounts = new uint256[](1);
      borrowAmounts[0] = amountToFlashloan;
      uint256[] memory modes = new uint256[](1);
      bytes memory flashloanParams = abi.encode(closeParams);
      aaveLendingPool.flashLoan(address(this), borrowAssets, borrowAmounts, modes, address(this), flashloanParams, 196);
    } else {
      // solhint-disable-next-line no-empty-blocks
      try optionMarketWrapper.closePosition(closeParams) {} catch {
        optionMarketWrapper.forceClosePosition(closeParams);
      }
    }

    // transfer withdrawn assets to recipient
    optionMarketAddresses.quoteAsset.transfer(recipient, optionMarketAddresses.quoteAsset.balanceOf(address(this)));
    optionMarketAddresses.baseAsset.transfer(recipient, optionMarketAddresses.baseAsset.balanceOf(address(this)));

    // transfer position nft back to msg.sender
    if (
      optionMarketAddresses.optionToken.getPositionState(closeParams.positionId) == IOptionToken.PositionState.ACTIVE
    ) {
      optionMarketAddresses.optionToken.transferFrom(address(this), msg.sender, closeParams.positionId);
    } else {
      address poolLogic = msg.sender;
      address factory = IPoolLogic(poolLogic).factory();
      address lyraOptionMarketWrapperContractGuard = IHasGuardInfo(factory).getContractGuard(
        address(optionMarketWrapper)
      );
      LyraOptionMarketWrapperContractGuard(lyraOptionMarketWrapperContractGuard).removeClosedPosition(
        poolLogic,
        address(closeParams.optionMarket),
        closeParams.positionId
      );
    }
  }

  /// @notice execute function of aave flash loan
  /// @dev This function is called after your contract has received the flash loaned amount
  /// @param assets the loaned assets
  /// @param amounts the loaned amounts per each asset
  /// @param premiums the additional owed amount per each asset
  /// @param originator the origin caller address of the flash loan
  /// @param params Variadic packed params to pass to the receiver as extra information
  function executeOperation(
    address[] memory assets,
    uint256[] memory amounts,
    uint256[] memory premiums,
    address originator,
    bytes memory params
  ) external returns (bool success) {
    require(msg.sender == address(aaveLendingPool) && originator == address(this), "invalid flashloan origin");
    require(assets.length == 1 && amounts.length == 1 && premiums.length == 1, "invalid length");

    IOptionMarketWrapper optionMarketWrapper = getOptionMarketWrapper();
    IOptionMarketWrapper.OptionPositionParams memory closeParams = abi.decode(
      params,
      (IOptionMarketWrapper.OptionPositionParams)
    );
    IOptionMarketWrapper.OptionMarketContracts memory optionMarketAddresses = optionMarketWrapper.marketContracts(
      closeParams.optionMarket
    );

    require(assets[0] == address(optionMarketAddresses.quoteAsset), "invalid asset");

    // close option position
    {
      optionMarketAddresses.quoteAsset.approve(address(optionMarketWrapper), amounts[0]);
      closeParams.inputAmount = amounts[0];
      // solhint-disable-next-line no-empty-blocks
      try optionMarketWrapper.closePosition(closeParams) {} catch {
        optionMarketWrapper.forceClosePosition(closeParams);
      }
    }

    // swap base assets to quote assets
    {
      uint256 baseAssetAmount = optionMarketAddresses.baseAsset.balanceOf(address(this));
      ISynthetixAdapter synthetixAdapter = getSynthetixAdapter();
      bytes32 synthQuoteKey = synthetixAdapter.quoteKey(address(closeParams.optionMarket));
      bytes32 synthBaseKey = synthetixAdapter.baseKey(address(closeParams.optionMarket));
      address synthetix = synthetixAdapter.synthetix();
      optionMarketAddresses.baseAsset.approve(synthetix, baseAssetAmount);
      ISynthetix(synthetix).exchange(synthBaseKey, baseAssetAmount, synthQuoteKey);
    }

    // payback amounts + premiums
    {
      optionMarketAddresses.quoteAsset.approve(address(aaveLendingPool), amounts[0].add(premiums[0]));
    }

    return true;
  }

  function getAmountOfQuoteToBorrow(IOptionMarketWrapper.OptionPositionParams memory closeParams)
    public
    view
    returns (uint256)
  {
    uint256 expectedCollateralReturned = closeParams.currentCollateral - closeParams.setCollateralTo;
    ISynthetixAdapter synthetixAdapter = getSynthetixAdapter();
    bytes32 synthQuoteKey = synthetixAdapter.quoteKey(address(closeParams.optionMarket));
    bytes32 synthBaseKey = synthetixAdapter.baseKey(address(closeParams.optionMarket));
    IExchanger exchanger = synthetixAdapter.exchanger();
    (uint256 amountReceived, , ) = exchanger.getAmountsForExchange(
      expectedCollateralReturned,
      synthBaseKey,
      synthQuoteKey
    );
    // we return 99% because we need a margin to cover flash fees
    return amountReceived.mul(99).div(100);
  }
}
