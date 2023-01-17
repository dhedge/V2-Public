

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#AaveLendingPoolGuardV2-txGuard-address-address-bytes-)

# Events:
- [`Deposit(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)`](#AaveLendingPoolGuardV2-Deposit-address-address-address-uint256-uint256-)
- [`Withdraw(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)`](#AaveLendingPoolGuardV2-Withdraw-address-address-address-uint256-uint256-)
- [`SetUserUseReserveAsCollateral(address fundAddress, address asset, bool useAsCollateral, uint256 time)`](#AaveLendingPoolGuardV2-SetUserUseReserveAsCollateral-address-address-bool-uint256-)
- [`Borrow(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)`](#AaveLendingPoolGuardV2-Borrow-address-address-address-uint256-uint256-)
- [`Repay(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)`](#AaveLendingPoolGuardV2-Repay-address-address-address-uint256-uint256-)
- [`SwapBorrowRateMode(address fundAddress, address asset, uint256 rateMode)`](#AaveLendingPoolGuardV2-SwapBorrowRateMode-address-address-uint256-)
- [`RebalanceStableBorrowRate(address fundAddress, address asset)`](#AaveLendingPoolGuardV2-RebalanceStableBorrowRate-address-address-)


# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#AaveLendingPoolGuardV2-txGuard-address-address-bytes-}
Transaction guard for Aave V2 Lending Pool


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data.

- isPublic if the transaction is public or private
















