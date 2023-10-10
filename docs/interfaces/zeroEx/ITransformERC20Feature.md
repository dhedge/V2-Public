

# Functions:
- [`transformERC20(contract IERC20 inputToken, contract IERC20 outputToken, uint256 inputTokenAmount, uint256 minOutputTokenAmount, struct ITransformERC20Feature.Transformation[] transformations)`](#ITransformERC20Feature-transformERC20-contract-IERC20-contract-IERC20-uint256-uint256-struct-ITransformERC20Feature-Transformation---)
- [`getTransformerDeployer()`](#ITransformERC20Feature-getTransformerDeployer--)



# Function `transformERC20(contract IERC20 inputToken, contract IERC20 outputToken, uint256 inputTokenAmount, uint256 minOutputTokenAmount, struct ITransformERC20Feature.Transformation[] transformations) → uint256 outputTokenAmount` {#ITransformERC20Feature-transformERC20-contract-IERC20-contract-IERC20-uint256-uint256-struct-ITransformERC20Feature-Transformation---}
No description

## Parameters:
- `inputToken`: The token being provided by the sender.
       If `0xeee...`, ETH is implied and should be provided with the call.`

- `outputToken`: The token to be acquired by the sender.
       `0xeee...` implies ETH.

- `inputTokenAmount`: The amount of `inputToken` to take from the sender.

- `minOutputTokenAmount`: The minimum amount of `outputToken` the sender
       must receive for the entire transformation to succeed.

- `transformations`: The transformations to execute on the token balance(s)
       in sequence.


## Return Values:
- outputTokenAmount The amount of `outputToken` received by the sender.


# Function `getTransformerDeployer() → address deployer` {#ITransformERC20Feature-getTransformerDeployer--}
No description


## Return Values:
- deployer The transform deployer address.


