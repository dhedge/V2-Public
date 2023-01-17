

# Functions:
- [`initialize(address _depositToken, address _payoutToken, address _treasury, uint256 _minBondPrice, uint256 _maxPayoutAvailable)`](#DynamicBonds-initialize-address-address-address-uint256-uint256-)
- [`bondOptions()`](#DynamicBonds-bondOptions--)
- [`getUserBonds(address _user)`](#DynamicBonds-getUserBonds-address-)
- [`setTreasury(address _treasury)`](#DynamicBonds-setTreasury-address-)
- [`setMinBondPrice(uint256 _minBondPrice)`](#DynamicBonds-setMinBondPrice-uint256-)
- [`setMaxPayoutAvailable(uint256 _maxPayoutAvailable)`](#DynamicBonds-setMaxPayoutAvailable-uint256-)
- [`setBondTerms(uint256 _payoutAvailable, uint256 _expiryTimestamp)`](#DynamicBonds-setBondTerms-uint256-uint256-)
- [`addBondOptions(struct DynamicBonds.BondOption[] _bondOptions)`](#DynamicBonds-addBondOptions-struct-DynamicBonds-BondOption---)
- [`updateBondOption(uint256 _index, struct DynamicBonds.BondOption _bondOption)`](#DynamicBonds-updateBondOption-uint256-struct-DynamicBonds-BondOption-)
- [`updateBondOptions(uint256[] _indexes, struct DynamicBonds.BondOption[] _bondOptions)`](#DynamicBonds-updateBondOptions-uint256---struct-DynamicBonds-BondOption---)
- [`deposit(uint256 _maxDepositAmount, uint256 _payoutAmount, uint256 _bondOptionIndex)`](#DynamicBonds-deposit-uint256-uint256-uint256-)
- [`claim(uint256 _bondId)`](#DynamicBonds-claim-uint256-)
- [`forceWithdraw(address _token, uint256 _amount)`](#DynamicBonds-forceWithdraw-address-uint256-)

# Events:
- [`SetBondTerms(uint256 payoutAvailable, uint256 expiryTimestamp)`](#DynamicBonds-SetBondTerms-uint256-uint256-)
- [`UpdateBondOption(uint256 index, struct DynamicBonds.BondOption bondOption)`](#DynamicBonds-UpdateBondOption-uint256-struct-DynamicBonds-BondOption-)
- [`UpdateBondOptions(uint256[] index, struct DynamicBonds.BondOption[] bondOption)`](#DynamicBonds-UpdateBondOptions-uint256---struct-DynamicBonds-BondOption---)
- [`AddBondOptions(struct DynamicBonds.BondOption[] bondOptions)`](#DynamicBonds-AddBondOptions-struct-DynamicBonds-BondOption---)
- [`Deposit(address user, uint256 bondId, uint256 payoutAmount, struct DynamicBonds.BondOption bondOption)`](#DynamicBonds-Deposit-address-uint256-uint256-struct-DynamicBonds-BondOption-)
- [`Claim(address user, uint256 bondId)`](#DynamicBonds-Claim-address-uint256-)


# Function `initialize(address _depositToken, address _payoutToken, address _treasury, uint256 _minBondPrice, uint256 _maxPayoutAvailable)` {#DynamicBonds-initialize-address-address-address-uint256-uint256-}
No description




# Function `bondOptions() → struct DynamicBonds.BondOption[]` {#DynamicBonds-bondOptions--}
No description




# Function `getUserBonds(address _user) → struct DynamicBonds.BondView[] bondsArray` {#DynamicBonds-getUserBonds-address-}
No description




# Function `setTreasury(address _treasury)` {#DynamicBonds-setTreasury-address-}
Update treasury


## Parameters:
- `_treasury`: new treasury address



# Function `setMinBondPrice(uint256 _minBondPrice)` {#DynamicBonds-setMinBondPrice-uint256-}
Update minimum principal price


## Parameters:
- `_minBondPrice`: minimum principal price



# Function `setMaxPayoutAvailable(uint256 _maxPayoutAvailable)` {#DynamicBonds-setMaxPayoutAvailable-uint256-}
Update maximum payout available


## Parameters:
- `_maxPayoutAvailable`: maximum payout available



# Function `setBondTerms(uint256 _payoutAvailable, uint256 _expiryTimestamp)` {#DynamicBonds-setBondTerms-uint256-uint256-}
Initializes the bond terms


## Parameters:
- `_payoutAvailable`: available payout amount

- `_expiryTimestamp`: expired timestamp



# Function `addBondOptions(struct DynamicBonds.BondOption[] _bondOptions)` {#DynamicBonds-addBondOptions-struct-DynamicBonds-BondOption---}
add bond options


## Parameters:
- `_bondOptions`: bond options





# Function `updateBondOption(uint256 _index, struct DynamicBonds.BondOption _bondOption)` {#DynamicBonds-updateBondOption-uint256-struct-DynamicBonds-BondOption-}
update bond option


## Parameters:
- `_index`: bond option index

- `_bondOption`: bond option



# Function `updateBondOptions(uint256[] _indexes, struct DynamicBonds.BondOption[] _bondOptions)` {#DynamicBonds-updateBondOptions-uint256---struct-DynamicBonds-BondOption---}
update bond options


## Parameters:
- `_indexes`: bond option index list

- `_bondOptions`: bond options list



# Function `deposit(uint256 _maxDepositAmount, uint256 _payoutAmount, uint256 _bondOptionIndex)` {#DynamicBonds-deposit-uint256-uint256-uint256-}
Creates a new bond for the user


## Parameters:
- `_payoutAmount`: payout amount

- `_bondOptionIndex`: bond option index



# Function `claim(uint256 _bondId)` {#DynamicBonds-claim-uint256-}
Transfers lockAmount to bondOwner after lockEndTimestamp


## Parameters:
- `_bondId`: bond index



# Function `forceWithdraw(address _token, uint256 _amount)` {#DynamicBonds-forceWithdraw-address-uint256-}
Withdraw ERC20 tokens


## Parameters:
- `_token`: ERC20 token address

- `_amount`: ERC20 token amount to withdraw



