

# Functions:
- [`deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)`](#IAaveV3Pool-deposit-address-uint256-address-uint16-)
- [`supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)`](#IAaveV3Pool-supply-address-uint256-address-uint16-)
- [`withdraw(address asset, uint256 amount, address to)`](#IAaveV3Pool-withdraw-address-uint256-address-)
- [`borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)`](#IAaveV3Pool-borrow-address-uint256-uint256-uint16-address-)
- [`repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf)`](#IAaveV3Pool-repay-address-uint256-uint256-address-)
- [`repayWithATokens(address asset, uint256 amount, uint256 rateMode)`](#IAaveV3Pool-repayWithATokens-address-uint256-uint256-)
- [`setUserUseReserveAsCollateral(address asset, bool useAsCollateral)`](#IAaveV3Pool-setUserUseReserveAsCollateral-address-bool-)
- [`rebalanceStableBorrowRate(address asset, address user)`](#IAaveV3Pool-rebalanceStableBorrowRate-address-address-)
- [`swapBorrowRateMode(address asset, uint256 rateMode)`](#IAaveV3Pool-swapBorrowRateMode-address-uint256-)
- [`getUserConfiguration(address user)`](#IAaveV3Pool-getUserConfiguration-address-)
- [`getConfiguration(address asset)`](#IAaveV3Pool-getConfiguration-address-)
- [`getUserAccountData(address user)`](#IAaveV3Pool-getUserAccountData-address-)
- [`getReserveData(address asset)`](#IAaveV3Pool-getReserveData-address-)
- [`flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes params, uint16 referralCode)`](#IAaveV3Pool-flashLoanSimple-address-address-uint256-bytes-uint16-)



# Function `deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)` {#IAaveV3Pool-deposit-address-uint256-address-uint16-}
No description




# Function `supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)` {#IAaveV3Pool-supply-address-uint256-address-uint16-}
No description




# Function `withdraw(address asset, uint256 amount, address to) → uint256` {#IAaveV3Pool-withdraw-address-uint256-address-}
No description




# Function `borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)` {#IAaveV3Pool-borrow-address-uint256-uint256-uint16-address-}
No description




# Function `repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) → uint256` {#IAaveV3Pool-repay-address-uint256-uint256-address-}
No description




# Function `repayWithATokens(address asset, uint256 amount, uint256 rateMode) → uint256` {#IAaveV3Pool-repayWithATokens-address-uint256-uint256-}
No description




# Function `setUserUseReserveAsCollateral(address asset, bool useAsCollateral)` {#IAaveV3Pool-setUserUseReserveAsCollateral-address-bool-}
No description




# Function `rebalanceStableBorrowRate(address asset, address user)` {#IAaveV3Pool-rebalanceStableBorrowRate-address-address-}
No description




# Function `swapBorrowRateMode(address asset, uint256 rateMode)` {#IAaveV3Pool-swapBorrowRateMode-address-uint256-}
No description




# Function `getUserConfiguration(address user) → struct IAaveV3Pool.UserConfigurationMap` {#IAaveV3Pool-getUserConfiguration-address-}
No description




# Function `getConfiguration(address asset) → struct IAaveV3Pool.ReserveConfigurationMap` {#IAaveV3Pool-getConfiguration-address-}
No description




# Function `getUserAccountData(address user) → uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor` {#IAaveV3Pool-getUserAccountData-address-}
No description




# Function `getReserveData(address asset) → struct IAaveV3Pool.ReserveData` {#IAaveV3Pool-getReserveData-address-}
No description




# Function `flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes params, uint16 referralCode)` {#IAaveV3Pool-flashLoanSimple-address-address-uint256-bytes-uint16-}
No description




