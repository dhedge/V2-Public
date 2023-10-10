import { ovmChainData } from "../../../../config/chainData/ovmData";
import { MaiVaultAssetGuardTest } from "../../common/mai/MaiVaultAssetGuardTest";

MaiVaultAssetGuardTest("ovm", {
  maiAddress: ovmChainData.assets.maiStableCoin,
  maiPriceFeed: ovmChainData.price_feeds.maiStableCoin,
  // Optimism MAI Vault (OPMVT)
  maiVaultAddress: "0xbf1aeA8670D2528E08334083616dD9C5F3B087aE",
  maiVaultCollateralAsset: ovmChainData.assets.op,
  maiVaultCollateralAssetBalanceOfSlot: ovmChainData.assetsBalanceOfSlot.op,
  usdc: ovmChainData.assets.usdc,
  aaveV3LendingPool: ovmChainData.aaveV3.lendingPool,
  // given to use by qi
  frontPromoter: 0,
});
