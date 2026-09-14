// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/v5/contracts/token/ERC20/utils/SafeERC20.sol";
import {ProxyAdmin} from "@openzeppelin/v5/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/v5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Test} from "forge-std/Test.sol";

import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {Swapper} from "contracts/swappers/swapper/Swapper.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {AggregatorsAPIHelper} from "./AggregatorsAPIHelper.sol";

struct Token {
  IERC20 token;
  IAggregatorV3Interface priceFeed;
}

/// @dev Chain-specific inputs supplied by the per-chain test contract.
struct ChainConfig {
  string networkAlias;
  uint256 forkBlockNumber;
  Token usdc;
  Token dai;
  Token rEth;
  Token weth;
}

/// @dev Deploys a fresh Swapper on a fork of the configured chain. The committed swapdata cache
///      (swapdatas-cache/swapper/<chainId>.json) is bound to the fork block and to the Swapper proxy address that
///      results from `admin` deploying the ProxyAdmin, the implementation and the proxy in that order, so keep the
///      deployment sequence below unchanged.
abstract contract SwapperTestSetup is Test {
  using SafeERC20 for IERC20;

  // Router addresses. Same on every chain and the same keys as the production Swapper (see readmes/swapper.md).
  address internal constant ONE_INCH_ROUTER_V6 = EthereumConfig.ONE_INCH_V6_ROUTER;
  address internal constant PARASWAP_ROUTER_V6 = 0x6A000F20005980200259B80c5102003040001068;
  address internal constant KYBER_SWAP_ROUTER_V2 = EthereumConfig.KYBER_SWAP_ROUTER_V2;

  // Permit2 related.
  address internal constant PERMIT2 = EthereumConfig.PERMIT2;

  // Router keys.
  bytes32 internal constant ONE_INCH_V6_ROUTER_KEY = bytes32("ONE_INCH");
  bytes32 internal constant PARASWAP_V6_ROUTER_KEY = bytes32("PARASWAP_V6");
  bytes32 internal constant KYBER_SWAP_V2_ROUTER_KEY = bytes32("KYBER_SWAP_V2");

  uint8 internal constant DEFAULT_SLIPPAGE = 1; // 1%
  uint8 internal constant TRANSFER_METHODS = 3; // Number of `TransferMethod` available. Refer to `SwapperStructs.TransferMethod`. Don't use the below technique to get the number of enum values.
  uint8 internal constant TOTAL_AGGREGATORS = uint8(type(AggregatorsAPIHelper.Aggregator).max) + 1; // Number of aggregators available. Refer to `Aggregator`.
  uint256 internal DEFAULT_AMOUNT = 250; // Can be converted to any token amount based on the token's decimals.

  string internal networkAlias;
  uint256 internal forkBlockNumber;

  address internal admin = makeAddr("admin");
  address internal alice;
  uint256 internal alicePrivateKey;

  bytes32 internal DOMAIN_SEPARATOR;

  // Token and Chainlink pricefeed addresses.
  Token internal USDC;
  Token internal DAI;
  Token internal rETH;
  Token internal WETH;

  ProxyAdmin internal proxyAdmin;
  Swapper internal swapperProxy;
  address internal swapperImplementation;

  constructor(ChainConfig memory config) {
    networkAlias = config.networkAlias;
    forkBlockNumber = config.forkBlockNumber;
    USDC = config.usdc;
    DAI = config.dai;
    rETH = config.rEth;
    WETH = config.weth;
  }

  function setUp() public virtual {
    vm.createSelectFork(networkAlias, forkBlockNumber);

    // Not the usual "alice": that well-known address carries EIP-7702 delegation code on Base mainnet, which makes
    // Permit2 verify her signatures via ERC-1271 and revert.
    (alice, alicePrivateKey) = makeAddrAndKey("swapper-alice");

    vm.startPrank(admin);
    proxyAdmin = new ProxyAdmin(admin);

    (bool success, bytes memory data) = PERMIT2.staticcall(abi.encodeWithSignature("DOMAIN_SEPARATOR()"));
    require(success, "Failed to fetch DOMAIN_SEPARATOR");

    DOMAIN_SEPARATOR = abi.decode(data, (bytes32));

    swapperImplementation = address(new Swapper());
    swapperProxy = Swapper(
      address(
        new TransparentUpgradeableProxy(
          swapperImplementation,
          admin, // OZ v5: initial owner of the ProxyAdmin the proxy deploys for itself
          abi.encodeCall(Swapper.initialize, (admin, PERMIT2, IWETH(address(WETH.token))))
        )
      )
    );

    vm.label(address(swapperProxy), "Swapper");

    // Add routers to the whitelist.
    swapperProxy.addRouter(ONE_INCH_V6_ROUTER_KEY, ONE_INCH_ROUTER_V6);
    swapperProxy.addRouter(PARASWAP_V6_ROUTER_KEY, PARASWAP_ROUTER_V6);
    swapperProxy.addRouter(KYBER_SWAP_V2_ROUTER_KEY, KYBER_SWAP_ROUTER_V2);

    fillWallets();
  }

  function fillWallets() internal {
    address[] memory tokens = new address[](4);
    tokens[0] = address(USDC.token);
    tokens[1] = address(DAI.token);
    tokens[2] = address(rETH.token);
    tokens[3] = address(WETH.token);

    for (uint256 i; i < tokens.length; ++i) {
      deal(tokens[i], alice, 100_000 * (10 ** IERC20Metadata(tokens[i]).decimals()));
    }
    deal(alice, 100_000 ether);

    vm.startPrank(alice);

    // Approve the permit2 contract for all tokens.
    for (uint256 i; i < tokens.length; ++i) {
      IERC20(tokens[i]).safeIncreaseAllowance(PERMIT2, type(uint256).max);
    }
  }
}
