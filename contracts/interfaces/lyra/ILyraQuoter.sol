// All credit goes to https://github.com/blue-searcher/lyra-quoter/blob/master/contracts/LyraQuoter.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "../../interfaces/lyra/ILyraRegistry.sol";
import "../../interfaces/lyra/IOptionMarketViewer.sol";
import "../../interfaces/lyra/IOptionMarketWrapper.sol";
import "../../interfaces/lyra/IOptionToken.sol";
import "../../interfaces/lyra/ISynthetixAdapter.sol";
import "../../interfaces/lyra/IGWAVOracle.sol";

interface ILyraQuoter {
  function quote(
    IOptionMarket _optionMarket,
    uint256 strikeId,
    uint256 iterations,
    IOptionMarket.OptionType optionType,
    uint256 amount,
    IOptionMarket.TradeDirection tradeDirection,
    bool isForceClose
  ) external view returns (uint256 totalPremium, uint256 totalFee);
}
