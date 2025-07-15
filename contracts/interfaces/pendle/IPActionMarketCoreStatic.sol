// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

/// @dev This is not a full interface
interface IPActionMarketCoreStatic {
  function swapExactPtForSyStatic(
    address market,
    uint256 exactPtIn
  ) external view returns (uint256 netSyOut, uint256 netSyFee, uint256 priceImpact, uint256 exchangeRateAfter);

  function swapExactPtForTokenStatic(
    address market,
    uint256 exactPtIn,
    address tokenOut
  )
    external
    view
    returns (
      uint256 netTokenOut,
      uint256 netSyToRedeem,
      uint256 netSyFee,
      uint256 priceImpact,
      uint256 exchangeRateAfter
    );

  function swapExactSyForPtStatic(
    address market,
    uint256 exactSyIn
  ) external view returns (uint256 netPtOut, uint256 netSyFee, uint256 priceImpact, uint256 exchangeRateAfter);

  function swapExactTokenForPtStatic(
    address market,
    address tokenIn,
    uint256 amountTokenIn
  )
    external
    view
    returns (uint256 netPtOut, uint256 netSyMinted, uint256 netSyFee, uint256 priceImpact, uint256 exchangeRateAfter);

  function swapPtForExactSyStatic(
    address market,
    uint256 exactSyOut
  ) external view returns (uint256 netPtIn, uint256 netSyFee, uint256 priceImpact, uint256 exchangeRateAfter);

  function swapSyForExactPtStatic(
    address market,
    uint256 exactPtOut
  ) external view returns (uint256 netSyIn, uint256 netSyFee, uint256 priceImpact, uint256 exchangeRateAfter);
}
