

# Functions:
- [`deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)`](#ILendingPool-deposit-address-uint256-address-uint16-)
- [`withdraw(address asset, uint256 amount, address to)`](#ILendingPool-withdraw-address-uint256-address-)
- [`borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)`](#ILendingPool-borrow-address-uint256-uint256-uint16-address-)
- [`repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf)`](#ILendingPool-repay-address-uint256-uint256-address-)
- [`setUserUseReserveAsCollateral(address asset, bool useAsCollateral)`](#ILendingPool-setUserUseReserveAsCollateral-address-bool-)
- [`rebalanceStableBorrowRate(address asset, address user)`](#ILendingPool-rebalanceStableBorrowRate-address-address-)
- [`swapBorrowRateMode(address asset, uint256 rateMode)`](#ILendingPool-swapBorrowRateMode-address-uint256-)
- [`getUserConfiguration(address user)`](#ILendingPool-getUserConfiguration-address-)
- [`getConfiguration(address asset)`](#ILendingPool-getConfiguration-address-)
- [`getUserAccountData(address user)`](#ILendingPool-getUserAccountData-address-)
- [`getReserveData(address asset)`](#ILendingPool-getReserveData-address-)



# Function `deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)` {#ILendingPool-deposit-address-uint256-address-uint16-}
No description




# Function `withdraw(address asset, uint256 amount, address to) → uint256` {#ILendingPool-withdraw-address-uint256-address-}
No description




# Function `borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)` {#ILendingPool-borrow-address-uint256-uint256-uint16-address-}
No description




# Function `repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) → uint256` {#ILendingPool-repay-address-uint256-uint256-address-}
No description




# Function `setUserUseReserveAsCollateral(address asset, bool useAsCollateral)` {#ILendingPool-setUserUseReserveAsCollateral-address-bool-}
No description




# Function `rebalanceStableBorrowRate(address asset, address user)` {#ILendingPool-rebalanceStableBorrowRate-address-address-}
No description




# Function `swapBorrowRateMode(address asset, uint256 rateMode)` {#ILendingPool-swapBorrowRateMode-address-uint256-}
No description




# Function `getUserConfiguration(address user) → struct ILendingPool.UserConfigurationMap` {#ILendingPool-getUserConfiguration-address-}
No description




# Function `getConfiguration(address asset) → struct ILendingPool.ReserveConfigurationMap` {#ILendingPool-getConfiguration-address-}
No description




# Function `getUserAccountData(address user) → uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor` {#ILendingPool-getUserAccountData-address-}
No description




# Function `getReserveData(address asset) → struct ILendingPool.ReserveData` {#ILendingPool-getReserveData-address-}
No description




