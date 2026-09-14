import { CrossChainBridgeStruct } from "../types/AcrossContractGuard";
import { ChainId } from "./chainIds";
import { Address } from "./types";
import { assets as arbitrumAssets, gmxTestVaults } from "./arbitrum/deploymentData";
import { assets as baseAssets, FLAT_MONEY_PERP_MARKET_BOT_TEST } from "./base/deploymentData";
import { assets as ethereumAssets, ondoHyperliquidMarketMaking as ondoVaults } from "./ethereum/deploymentData";
import {
  assets as hyperevmAssets,
  ondoHyperliquidMarketMaking as hyperApiWalletVaults,
} from "./hyperevm/deploymentData";
import { assets as ovmAssets, flatMoneyV2Vaults } from "./ovm/deploymentData";

interface BridgeEnd {
  chainId: number;
  pool: Address;
  token: Address;
}

// Each route is written once and approved in both directions: the AcrossContractGuard on either chain
// lets the pool at that end bridge its token to the pool at the other end.
const routes: [BridgeEnd, BridgeEnd][] = [
  [
    { chainId: ChainId.arbitrum, pool: gmxTestVaults.gmxTest2, token: arbitrumAssets.usdcNative },
    { chainId: ChainId.base, pool: FLAT_MONEY_PERP_MARKET_BOT_TEST, token: baseAssets.usdc },
  ],
  [
    { chainId: ChainId.arbitrum, pool: gmxTestVaults.gmxTest6, token: arbitrumAssets.usdcNative },
    { chainId: ChainId.base, pool: FLAT_MONEY_PERP_MARKET_BOT_TEST, token: baseAssets.usdc },
  ],
  [
    { chainId: ChainId.arbitrum, pool: gmxTestVaults.gmxTest2, token: arbitrumAssets.usdcNative },
    { chainId: ChainId.optimism, pool: flatMoneyV2Vaults.flatMoneyV2MarketMaker, token: ovmAssets.usdcNative },
  ],
  [
    { chainId: ChainId.ethereum, pool: ondoVaults.ondoVault, token: ethereumAssets.usdc },
    { chainId: ChainId.hyperevm, pool: hyperApiWalletVaults.hyperApiWalletVault, token: hyperevmAssets.usdc },
  ],
  [
    { chainId: ChainId.ethereum, pool: ondoVaults.ondoVault2, token: ethereumAssets.usdc },
    { chainId: ChainId.hyperevm, pool: hyperApiWalletVaults.hyperApiWalletVault2, token: hyperevmAssets.usdc },
  ],
  [
    { chainId: ChainId.ethereum, pool: ondoVaults.ondoVault3, token: ethereumAssets.usdc },
    { chainId: ChainId.hyperevm, pool: hyperApiWalletVaults.hyperApiWalletVault3, token: hyperevmAssets.usdc },
  ],
];

export const getAcrossApprovedDestinations = (chainId: number): CrossChainBridgeStruct[] =>
  routes
    .flatMap(([a, b]): [BridgeEnd, BridgeEnd][] => [
      [a, b],
      [b, a],
    ])
    .filter(([source]) => source.chainId === chainId)
    .map(([source, destination]) => ({
      sourcePool: source.pool,
      sourceToken: source.token,
      destinationChainId: destination.chainId,
      destinationPool: destination.pool,
      destinationToken: destination.token,
    }));
