// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestEthereum} from "test/integration/ethereum/aaveV3/AaveV3TestEthereum.t.sol";
import {KyberSwapAPIHelper} from "test/integration/common/kyberSwap/KyberSwapAPIHelper.sol";
import {AaveV3TestFFI} from "test/integration/ffi/common/aave/AaveV3TestFFI.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract AaveV3TestFFIEthereum is AaveV3TestFFI, AaveV3TestEthereum {
  constructor() AaveV3TestFFI(EthereumConfig.CHAIN_ID) AaveV3TestEthereum() {}

  function setUp() public override(AaveV3TestFFI, AaveV3TestEthereum) {
    super.setUp();
  }

  function _getSwapData(
    uint256 srcAmount,
    address srcToken,
    address destToken
  ) internal override returns (bytes32 routerKey, bytes memory swapData) {
    KyberSwapAPIHelper.KyberSwapData memory params = KyberSwapAPIHelper.KyberSwapData({
      srcAmount: srcAmount,
      srcToken: srcToken,
      destToken: destToken,
      user: swapper,
      slippageBPS: 100
    });

    (, swapData) = getDataFromKyberSwap(params, EthereumConfig.CHAIN_ID);
    routerKey = bytes32("KYBER_SWAP_V2");
  }

  function _getCacheDirectoryPath() internal pure override returns (string memory directoryPath) {
    return "swapdatas-cache/kyber-swap/";
  }
}
