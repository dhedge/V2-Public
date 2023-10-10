Contract to check for accumulated slippage impact for a poolManager.


# Functions:
- [`constructor(address _poolFactory, uint64 _decayTime, uint128 _maxCumulativeSlippage)`](#SlippageAccumulator-constructor-address-uint64-uint128-)
- [`updateSlippageImpact(struct SlippageAccumulator.SwapData swapData)`](#SlippageAccumulator-updateSlippageImpact-struct-SlippageAccumulator-SwapData-)
- [`getCumulativeSlippageImpact(address poolManagerLogic)`](#SlippageAccumulator-getCumulativeSlippageImpact-address-)
- [`setDecayTime(uint64 newDecayTime)`](#SlippageAccumulator-setDecayTime-uint64-)
- [`setMaxCumulativeSlippage(uint128 newMaxCumulativeSlippage)`](#SlippageAccumulator-setMaxCumulativeSlippage-uint128-)

# Events:
- [`DecayTimeChanged(uint64 oldDecayTime, uint64 newDecayTime)`](#SlippageAccumulator-DecayTimeChanged-uint64-uint64-)
- [`MaxCumulativeSlippageChanged(uint128 oldMaxCumulativeSlippage, uint128 newMaxCumulativeSlippage)`](#SlippageAccumulator-MaxCumulativeSlippageChanged-uint128-uint128-)


# Function `constructor(address _poolFactory, uint64 _decayTime, uint128 _maxCumulativeSlippage)` {#SlippageAccumulator-constructor-address-uint64-uint128-}
No description




# Function `updateSlippageImpact(struct SlippageAccumulator.SwapData swapData)` {#SlippageAccumulator-updateSlippageImpact-struct-SlippageAccumulator-SwapData-}
Updates the cumulative slippage impact and reverts if it's beyond limit.


## Parameters:
- `swapData`: Common swap data for all guards.





# Function `getCumulativeSlippageImpact(address poolManagerLogic) → uint128 cumulativeSlippage` {#SlippageAccumulator-getCumulativeSlippageImpact-address-}
Function to get the cumulative slippage adjusted using decayTime (current cumulative slippage impact).


## Parameters:
- `poolManagerLogic`: Address of the poolManager whose cumulative impact is stored.



# Function `setDecayTime(uint64 newDecayTime)` {#SlippageAccumulator-setDecayTime-uint64-}
Function to change decay time for calculating price impact.


## Parameters:
- `newDecayTime`: The new decay time (in seconds).



# Function `setMaxCumulativeSlippage(uint128 newMaxCumulativeSlippage)` {#SlippageAccumulator-setMaxCumulativeSlippage-uint128-}
Function to change the max acceptable cumulative slippage impact.


## Parameters:
- `newMaxCumulativeSlippage`: The new max acceptable cumulative slippage impact.



