Allows for fixed exchange rate swaps of an original token to an exchange token
Only a specified user account can interact with the contract
User can withdraw original token balance also

# Functions:
- [`constructor(contract IERC20 _originalToken, contract IERC20 _exchangeToken, uint256 _exchangeRate, address _user)`](#PrivateTokenSwap-constructor-contract-IERC20-contract-IERC20-uint256-address-)
- [`withdraw()`](#PrivateTokenSwap-withdraw--)
- [`swapAll()`](#PrivateTokenSwap-swapAll--)
- [`withdrawAdmin(contract IERC20 _token, uint256 _amount)`](#PrivateTokenSwap-withdrawAdmin-contract-IERC20-uint256-)
- [`setExchangeRate(uint256 _exchangeRate)`](#PrivateTokenSwap-setExchangeRate-uint256-)
- [`getExchangeRateAdjusted()`](#PrivateTokenSwap-getExchangeRateAdjusted--)



# Function `constructor(contract IERC20 _originalToken, contract IERC20 _exchangeToken, uint256 _exchangeRate, address _user)` {#PrivateTokenSwap-constructor-contract-IERC20-contract-IERC20-uint256-address-}
No description




# Function `withdraw()` {#PrivateTokenSwap-withdraw--}
Allows the user to withdraw the original token but only if there are exchange tokens in the contract





# Function `swapAll()` {#PrivateTokenSwap-swapAll--}
Allows the user to exchange their original token for the exchange token at the fixed price
It takes as much as possible from the user's wallet of the original token to swap




# Function `withdrawAdmin(contract IERC20 _token, uint256 _amount)` {#PrivateTokenSwap-withdrawAdmin-contract-IERC20-uint256-}
Allows the contract owner to withdraw any ERC20 token in the contract




# Function `setExchangeRate(uint256 _exchangeRate)` {#PrivateTokenSwap-setExchangeRate-uint256-}
No description




# Function `getExchangeRateAdjusted() → uint256 exchangeRateAdjusted` {#PrivateTokenSwap-getExchangeRateAdjusted--}
Gets a decimals adjusted exchange rate




