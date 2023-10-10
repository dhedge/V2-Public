

# Functions:
- [`postTradeDetails(int256 sizeDelta, uint256 tradePrice, enum IPerpsV2Market.OrderType orderType, address sender)`](#IPerpsV2Market-postTradeDetails-int256-uint256-enum-IPerpsV2Market-OrderType-address-)
- [`fillPrice(int256 sizeDelta)`](#IPerpsV2Market-fillPrice-int256-)
- [`resolver()`](#IPerpsV2Market-resolver--)
- [`positions(address account)`](#IPerpsV2Market-positions-address-)
- [`remainingMargin(address account)`](#IPerpsV2Market-remainingMargin-address-)
- [`accessibleMargin(address account)`](#IPerpsV2Market-accessibleMargin-address-)
- [`canLiquidate(address account)`](#IPerpsV2Market-canLiquidate-address-)
- [`orderFee(int256 sizeDelta, enum IPerpsV2Market.OrderType orderType)`](#IPerpsV2Market-orderFee-int256-enum-IPerpsV2Market-OrderType-)
- [`liquidatePosition(address account)`](#IPerpsV2Market-liquidatePosition-address-)
- [`modifyPosition(int256 sizeDelta, uint256 desiredFillPrice)`](#IPerpsV2Market-modifyPosition-int256-uint256-)
- [`modifyPositionWithTracking(int256 sizeDelta, uint256 desiredFillPrice, bytes32 trackingCode)`](#IPerpsV2Market-modifyPositionWithTracking-int256-uint256-bytes32-)
- [`transferMargin(int256 marginDelta)`](#IPerpsV2Market-transferMargin-int256-)
- [`withdrawAllMargin()`](#IPerpsV2Market-withdrawAllMargin--)
- [`closePosition(uint256 desiredFillPrice)`](#IPerpsV2Market-closePosition-uint256-)
- [`closePositionWithTracking(uint256 desiredFillPrice, bytes32 trackingCode)`](#IPerpsV2Market-closePositionWithTracking-uint256-bytes32-)
- [`submitOffchainDelayedOrder(int256 sizeDelta, uint256 desiredFillPrice)`](#IPerpsV2Market-submitOffchainDelayedOrder-int256-uint256-)
- [`submitOffchainDelayedOrderWithTracking(int256 sizeDelta, uint256 desiredFillPrice, bytes32 trackingCode)`](#IPerpsV2Market-submitOffchainDelayedOrderWithTracking-int256-uint256-bytes32-)
- [`executeOffchainDelayedOrder(address account, bytes[] priceUpdateData)`](#IPerpsV2Market-executeOffchainDelayedOrder-address-bytes---)
- [`cancelOffchainDelayedOrder(address account)`](#IPerpsV2Market-cancelOffchainDelayedOrder-address-)
- [`submitDelayedOrder(int256 sizeDelta, uint256 desiredFillPrice, uint256 desiredTimeDelta)`](#IPerpsV2Market-submitDelayedOrder-int256-uint256-uint256-)
- [`submitDelayedOrderWithTracking(int256 sizeDelta, uint256 desiredFillPrice, uint256 desiredTimeDelta, bytes32 trackingCode)`](#IPerpsV2Market-submitDelayedOrderWithTracking-int256-uint256-uint256-bytes32-)
- [`cancelDelayedOrder(address account)`](#IPerpsV2Market-cancelDelayedOrder-address-)
- [`delayedOrders(address account)`](#IPerpsV2Market-delayedOrders-address-)



# Function `postTradeDetails(int256 sizeDelta, uint256 tradePrice, enum IPerpsV2Market.OrderType orderType, address sender) → uint256 margin, int256 size, uint256 price, uint256 liqPrice, uint256 fee, enum IPerpsV2Market.Status status` {#IPerpsV2Market-postTradeDetails-int256-uint256-enum-IPerpsV2Market-OrderType-address-}
No description




# Function `fillPrice(int256 sizeDelta) → uint256 price, bool invalid` {#IPerpsV2Market-fillPrice-int256-}
No description




# Function `resolver() → contract IAddressResolver` {#IPerpsV2Market-resolver--}
No description




# Function `positions(address account) → struct IPerpsV2Market.Position` {#IPerpsV2Market-positions-address-}
No description




# Function `remainingMargin(address account) → uint256 marginRemaining, bool invalid` {#IPerpsV2Market-remainingMargin-address-}
No description




# Function `accessibleMargin(address account) → uint256 marginAccessible, bool invalid` {#IPerpsV2Market-accessibleMargin-address-}
No description




# Function `canLiquidate(address account) → bool` {#IPerpsV2Market-canLiquidate-address-}
No description




# Function `orderFee(int256 sizeDelta, enum IPerpsV2Market.OrderType orderType) → uint256 fee, bool invalid` {#IPerpsV2Market-orderFee-int256-enum-IPerpsV2Market-OrderType-}
No description




# Function `liquidatePosition(address account)` {#IPerpsV2Market-liquidatePosition-address-}
No description




# Function `modifyPosition(int256 sizeDelta, uint256 desiredFillPrice)` {#IPerpsV2Market-modifyPosition-int256-uint256-}
No description




# Function `modifyPositionWithTracking(int256 sizeDelta, uint256 desiredFillPrice, bytes32 trackingCode)` {#IPerpsV2Market-modifyPositionWithTracking-int256-uint256-bytes32-}
No description




# Function `transferMargin(int256 marginDelta)` {#IPerpsV2Market-transferMargin-int256-}
No description




# Function `withdrawAllMargin()` {#IPerpsV2Market-withdrawAllMargin--}
No description




# Function `closePosition(uint256 desiredFillPrice)` {#IPerpsV2Market-closePosition-uint256-}
No description




# Function `closePositionWithTracking(uint256 desiredFillPrice, bytes32 trackingCode)` {#IPerpsV2Market-closePositionWithTracking-uint256-bytes32-}
No description




# Function `submitOffchainDelayedOrder(int256 sizeDelta, uint256 desiredFillPrice)` {#IPerpsV2Market-submitOffchainDelayedOrder-int256-uint256-}
No description




# Function `submitOffchainDelayedOrderWithTracking(int256 sizeDelta, uint256 desiredFillPrice, bytes32 trackingCode)` {#IPerpsV2Market-submitOffchainDelayedOrderWithTracking-int256-uint256-bytes32-}
No description




# Function `executeOffchainDelayedOrder(address account, bytes[] priceUpdateData)` {#IPerpsV2Market-executeOffchainDelayedOrder-address-bytes---}
No description




# Function `cancelOffchainDelayedOrder(address account)` {#IPerpsV2Market-cancelOffchainDelayedOrder-address-}
No description




# Function `submitDelayedOrder(int256 sizeDelta, uint256 desiredFillPrice, uint256 desiredTimeDelta)` {#IPerpsV2Market-submitDelayedOrder-int256-uint256-uint256-}
No description




# Function `submitDelayedOrderWithTracking(int256 sizeDelta, uint256 desiredFillPrice, uint256 desiredTimeDelta, bytes32 trackingCode)` {#IPerpsV2Market-submitDelayedOrderWithTracking-int256-uint256-uint256-bytes32-}
No description




# Function `cancelDelayedOrder(address account)` {#IPerpsV2Market-cancelDelayedOrder-address-}
No description




# Function `delayedOrders(address account) → struct IPerpsV2Market.DelayedOrder` {#IPerpsV2Market-delayedOrders-address-}
No description




