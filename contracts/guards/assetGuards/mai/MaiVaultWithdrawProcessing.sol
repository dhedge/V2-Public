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
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../../contractGuards/MaiVaultContractGuard.sol";
import "../ClosedAssetGuard.sol";
import "../../../interfaces/IERC20Extended.sol";
import "../../../interfaces/IPoolLogic.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/aave/v3/IAaveV3Pool.sol";
import "../../../interfaces/uniswapV2/IUniswapV2RouterSwapOnly.sol";
import "../../../interfaces/mai/IStableQiVault.sol";

/// @title MaiVaultWithdrawProcessing
/// @dev inherited by MaiVaultAssetGuard contains withdrawProcessing with flashloan logic
abstract contract MaiVaultWithdrawProcessing is ClosedAssetGuard {
  using SafeMath for uint256;

  struct FlashParams {
    address swapRouter;
    address vault;
    uint256 vaultId;
    uint256 collateralPortion;
    uint256 debtPortionInMai;
  }

  address public immutable usdc;
  IAaveV3Pool public immutable aaveLendingPool;

  // the promoter id provided by mai
  uint256 public constant PROMOTER_ID = 0;

  constructor(address _usdc, address _aaveLendingPoolV3) {
    usdc = _usdc;
    aaveLendingPool = IAaveV3Pool(_aaveLendingPoolV3);
  }

  /// @notice Creates transaction data for reducing a futures position by the portion
  /// @param pool Pool address
  /// @param asset MaiVault
  /// @param portion The fraction of total future asset to withdraw
  /// @param withdrawerAddress Who the withdrawer is
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the reduction of the futures position in PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 portion,
    address withdrawerAddress
  )
    external
    view
    virtual
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    address maiVaultContactGuard = IHasGuardInfo(IPoolLogic(pool).factory()).getContractGuard(asset);
    uint256[] memory vaultIds = MaiVaultContractGuard(maiVaultContactGuard).getNftIds(pool, asset);

    // create the transactions array
    transactions = new MultiTransaction[](vaultIds.length * 2);
    uint256 txCount;
    for (uint256 i = 0; i < vaultIds.length; i++) {
      uint256 vaultId = vaultIds[i];
      // Transfer the Vault NFT ownership to this contract for processWithdrawAndReturn
      transactions[txCount].to = address(asset);
      transactions[txCount].txData = abi.encodeWithSelector(
        IERC721.transferFrom.selector,
        pool,
        address(this),
        vaultId
      );
      txCount++;

      // Will call processWithdrawAndReturn which processes the withdraw and then returns the vault to the pool
      transactions[txCount].to = address(this);
      transactions[txCount].txData = abi.encodeWithSelector(
        MaiVaultWithdrawProcessing.processWithdrawAndReturn.selector,
        asset,
        vaultId,
        portion,
        withdrawerAddress // recipient
      );
      txCount++;
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice This function is called upstream by the pool during withdraw processing after it has transferred the vault to this contract
  /// @dev it takes a flashloan from aave and pays down the portion of debt and then withdraws collateral to withdrawer, returns the vault to the pool
  /// @param vault MaiVault
  /// @param vaultId the vault nftID
  /// @param portion the withdrawers portion
  /// @param withdrawer the withdrawers address
  function processWithdrawAndReturn(address vault, uint256 vaultId, uint256 portion, address withdrawer) external {
    address factory = IPoolLogic(msg.sender).factory();
    IStableQiVault maiVault = IStableQiVault(vault);

    // This updates the vaults debt - used by qi when streaming fees are enabled
    uint256 debtAmountInMai = maiVault.updateVaultDebt(vaultId);
    uint256 collateralAmount = maiVault.vaultCollateral(vaultId);
    uint256 debtPortionInMai = debtAmountInMai.mul(portion).div(10 ** 18);
    uint256 collateralPortion = maiVault.vaultCollateral(vaultId).mul(portion).div(10 ** 18);
    address swapRouter = IHasGuardInfo(factory).getAddress("swapRouter");

    if (collateralAmount != 0) {
      if (debtPortionInMai != 0) {
        // Mai takes a fee denominated in the vaults collateral
        // We need to deduct the fee from their collateral
        uint256 fee = maiVault.calculateFee(maiVault.closingFee(), debtAmountInMai, maiVault.promoter(PROMOTER_ID));
        collateralPortion = collateralPortion.sub(fee);

        // assetValue is 10**18 usdc is 10**6 + 1% buffer
        uint256 usdBorrowAmount = IPoolManagerLogic(IPoolLogic(msg.sender).poolManagerLogic())
          .assetValue(maiVault.mai(), debtPortionInMai)
          .div(10 ** 12)
          .mul(103)
          .div(100);
        bytes memory params = abi.encode(
          FlashParams({
            swapRouter: swapRouter,
            vault: vault,
            vaultId: vaultId,
            collateralPortion: collateralPortion,
            debtPortionInMai: debtPortionInMai
          })
        );

        aaveLendingPool.flashLoanSimple(address(this), usdc, usdBorrowAmount, params, 0);
        // After flashLoanSimple, executeOperation will get called in this contract
      } else {
        maiVault.withdrawCollateral(vaultId, collateralPortion);
        convertCollateralToUsdc(swapRouter, maiVault.collateral(), collateralPortion, 0);
      }

      IERC20Extended(usdc).transfer(withdrawer, IERC20Extended(usdc).balanceOf(address(this)));
    }

    maiVault.transferFrom(address(this), msg.sender, vaultId);
  }

  /// @notice execute function of aave flash loan
  /// @dev This function buys mai, pays down the debt and withdraws collateral
  /// @param usdcAmount the loaned amount
  /// @param premium the additional owed amount
  /// @param initiator the origin caller address of the flash loan
  /// @param params Variadic packed params to pass to the receiver as extra information
  function executeOperation(
    address, // usdcAsset
    uint256 usdcAmount,
    uint256 premium,
    address initiator,
    bytes calldata params
  ) public returns (bool) {
    require(initiator == address(this), "only pool flash loan origin");

    FlashParams memory flashParams = abi.decode(params, (FlashParams));

    IStableQiVault maiVault = IStableQiVault(flashParams.vault);

    buyMai(flashParams.swapRouter, maiVault.mai(), flashParams.debtPortionInMai, usdcAmount);

    IERC20Extended(maiVault.mai()).approve(address(maiVault), flashParams.debtPortionInMai);
    maiVault.payBackToken(flashParams.vaultId, flashParams.debtPortionInMai, PROMOTER_ID);
    // We must withdraw collateral here so we can pay back our flashloan debt
    maiVault.withdrawCollateral(flashParams.vaultId, flashParams.collateralPortion);

    uint256 totalAaveUsdcDebt = usdcAmount.add(premium);
    convertCollateralToUsdc(
      flashParams.swapRouter,
      maiVault.collateral(),
      flashParams.collateralPortion,
      totalAaveUsdcDebt
    );
    // Approve aave to take back the flashloan debt
    IERC20Extended(usdc).approve(address(msg.sender), totalAaveUsdcDebt);
    return true;
  }

  /// @notice Buys Mai with usdc using swapExactTokensForTokens and converts overages back to usdc
  /// @param swapRouter MaiVault
  /// @param mai the vault nftID
  /// @param maiAmount the withdrawers portion
  /// @param usdcAmount the withdrawers address
  function buyMai(address swapRouter, address mai, uint256 maiAmount, uint256 usdcAmount) private {
    address[] memory path = new address[](2);
    path[0] = usdc;
    path[1] = mai;

    IERC20Extended(usdc).approve(swapRouter, usdcAmount);
    IUniswapV2RouterSwapOnly(swapRouter).swapExactTokensForTokens(
      usdcAmount,
      maiAmount,
      path,
      address(this),
      uint256(-1)
    );

    // We can have excess mai here because we don't use swapTokensForExactTokens
    uint256 over = IERC20Extended(mai).balanceOf(address(this)).sub(maiAmount);
    IERC20Extended(mai).approve(swapRouter, over);
    path[0] = mai;
    path[1] = usdc;
    IUniswapV2RouterSwapOnly(swapRouter).swapExactTokensForTokens(over, 0, path, address(this), uint256(-1));
  }

  /// @notice This function only works for erc20 collateral
  /// @dev if we want to support other collateral types (i.e lp pairs) we will need to update this
  /// @param swapRouter swapRouter
  /// @param collateral the vault collateral address
  /// @param collateralAmount the amount of collateral to swap
  /// @param minUsdc the minUsdc to get out
  function convertCollateralToUsdc(
    address swapRouter,
    address collateral,
    uint256 collateralAmount,
    uint256 minUsdc
  ) private {
    address[] memory path = new address[](2);
    path[0] = collateral;
    path[1] = usdc;
    IERC20Extended(collateral).approve(swapRouter, collateralAmount);
    IUniswapV2RouterSwapOnly(swapRouter).swapExactTokensForTokens(
      collateralAmount,
      minUsdc,
      path,
      address(this),
      uint256(-1)
    );
  }
}
