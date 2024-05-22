//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../../interfaces/IERC20Extended.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IManaged.sol";
import "../../interfaces/uniswapV2/IUniswapV2RouterSwapOnly.sol";
import "./EasySwapperWithdrawer.sol";
import "./EasySwapperStructs.sol";
import "./EasySwapperSwap.sol";

contract DhedgeEasySwapper is OwnableUpgradeable {
  using SafeMathUpgradeable for uint256;

  event Deposit(
    address pool,
    address depositor,
    address depositAsset,
    uint256 amount,
    address poolDepositAsset,
    uint256 liquidityMinted
  );

  address payable public feeSink;
  uint256 public feeNumerator;
  uint256 public feeDenominator;

  mapping(address => bool) public allowedPools;
  mapping(address => bool) public managerFeeBypass;

  EasySwapperStructs.WithdrawProps public withdrawProps;

  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}

  // solhint-disable-next-line no-empty-blocks
  fallback() external payable {}

  modifier isPoolAllowed(address _address) {
    require(allowedPools[_address], "no-go");
    _;
  }

  /// @param _feeSink Address of the fee recipient
  /// @param _feeNumerator Fee numerator ie 1
  /// @param _feeDenominator Fee denominator ie 100
  function initialize(address payable _feeSink, uint256 _feeNumerator, uint256 _feeDenominator) external initializer {
    __Ownable_init();

    feeSink = _feeSink;
    feeNumerator = _feeNumerator;
    feeDenominator = _feeDenominator;
  }

  /// @notice Sets the WithdrawProps
  /// @param _withdrawProps the new withdrawProps
  function setWithdrawProps(EasySwapperStructs.WithdrawProps calldata _withdrawProps) external onlyOwner {
    withdrawProps = _withdrawProps;
  }

  /// @notice Allows the swap router to be updated
  /// @param _swapRouter the address of a UniV2 compatible router
  function setSwapRouter(IUniswapV2RouterSwapOnly _swapRouter) external onlyOwner {
    withdrawProps.swapRouter = _swapRouter;
  }

  /// @notice Sets if a pool is allowed to use the custom cooldown deposit functions
  /// @param pool the pool for the setting
  /// @param allowed if the pool is allowed, can be used to remove pool
  function setPoolAllowed(address pool, bool allowed) external onlyOwner {
    allowedPools[pool] = allowed;
  }

  /// @notice Sets the deposit fee, thats charged to the user
  /// @dev 50:10000 50bp
  /// @param numerator the numerator ie 1
  /// @param denominator he denominator ie 100
  function setFee(uint256 numerator, uint256 denominator) external onlyOwner {
    require(feeDenominator >= feeNumerator, "nmr<=dnmr");
    feeNumerator = numerator;
    feeDenominator = denominator;
  }

  /// @notice Sets where the deposit fee is sent
  /// @param sink the address of the fee receipient
  function setFeeSink(address payable sink) external onlyOwner {
    feeSink = sink;
  }

  /// @notice Bypasses the fee for a pool manager
  /// @param manager Manager to bypass the fee for
  /// @param bypass Enable / disable bypass
  function setManagerFeeBypass(address manager, bool bypass) external onlyOwner {
    managerFeeBypass[manager] = bypass;
  }

  /// @notice deposit into underlying pool and receive tokens with normal lockup
  /// @param pool the pool to deposit into
  /// @param depositAsset the asset the user wants to deposit
  /// @param amount the amount of the deposit asset
  /// @param poolDepositAsset the asset that the pool accepts
  /// @param expectedLiquidityMinted the expected amount of pool tokens to receive (slippage protection)
  /// @return liquidityMinted the number of wrapper tokens allocated
  function deposit(
    address pool,
    IERC20Extended depositAsset,
    uint256 amount,
    IERC20Extended poolDepositAsset,
    uint256 expectedLiquidityMinted
  ) external returns (uint256 liquidityMinted) {
    // Transfer the users funds to this contract
    IERC20Extended(address(depositAsset)).transferFrom(msg.sender, address(this), amount);

    return _deposit(pool, depositAsset, amount, poolDepositAsset, expectedLiquidityMinted, false);
  }

  /// @notice deposit into underlying pool and receive tokens with 15 minutes lockup
  /// @dev function name mimics the naming of PoolLogic's function
  /// @param pool the pool to deposit into
  /// @param depositAsset the asset the user wants to deposit
  /// @param amount the amount of the deposit asset
  /// @param poolDepositAsset the asset that the pool accepts
  /// @param expectedLiquidityMinted the expected amount of pool tokens to receive (slippage protection)
  /// @return liquidityMinted the number of wrapper tokens allocated
  function depositWithCustomCooldown(
    address pool,
    IERC20Extended depositAsset,
    uint256 amount,
    IERC20Extended poolDepositAsset,
    uint256 expectedLiquidityMinted
  ) external isPoolAllowed(pool) returns (uint256 liquidityMinted) {
    // Transfer the users funds to this contract
    IERC20Extended(address(depositAsset)).transferFrom(msg.sender, address(this), amount);

    return _deposit(pool, depositAsset, amount, poolDepositAsset, expectedLiquidityMinted, true);
  }

  /// @notice deposit native asset into underlying pool and receive tokens with normal lockup
  /// @param pool the pool to deposit into
  /// @param poolDepositAsset the asset that the pool accepts
  /// @param expectedLiquidityMinted the expected amount of pool tokens to receive (slippage protection)
  /// @return liquidityMinted the number of wrapper tokens allocated
  function depositNative(
    address pool,
    IERC20Extended poolDepositAsset,
    uint256 expectedLiquidityMinted
  ) external payable returns (uint256 liquidityMinted) {
    // wrap native asset
    uint256 amount = msg.value;
    IERC20Extended depositAsset = withdrawProps.nativeAssetWrapper;
    IWETH(address(depositAsset)).deposit{value: amount}();

    return _deposit(pool, depositAsset, amount, poolDepositAsset, expectedLiquidityMinted, false);
  }

  /// @notice deposit native asset into underlying pool and receive tokens with 15 minutes lockup
  /// @dev Function name mimics the naming of PoolLogic's function
  /// @param pool the pool to deposit into
  /// @param poolDepositAsset the asset that the pool accepts
  /// @param expectedLiquidityMinted the expected amount of pool tokens to receive (slippage protection)
  /// @return liquidityMinted the number of wrapper tokens allocated
  function depositNativeWithCustomCooldown(
    address pool,
    IERC20Extended poolDepositAsset,
    uint256 expectedLiquidityMinted
  ) external payable isPoolAllowed(pool) returns (uint256 liquidityMinted) {
    // wrap native asset
    uint256 amount = msg.value;
    IERC20Extended depositAsset = withdrawProps.nativeAssetWrapper;
    IWETH(address(depositAsset)).deposit{value: amount}();

    return _deposit(pool, depositAsset, amount, poolDepositAsset, expectedLiquidityMinted, true);
  }

  /// @notice Swaps deposit asset into pool deposit asset and deposits into the pool
  /// @dev Boolean flag is used as last param not to exceed contract size limit
  /// @param pool the pool to deposit into
  /// @param depositAsset the asset the user wants to deposit
  /// @param amount the amount of the deposit asset
  /// @param poolDepositAsset the asset that the pool accepts
  /// @param expectedLiquidityMinted the expected amount of pool tokens to receive (slippage protection)
  /// @param customCooldown boolean to choose between normal deposit and custom cooldown deposit
  /// @return liquidityMinted the number of wrapper tokens allocated
  function _deposit(
    address pool,
    IERC20Extended depositAsset,
    uint256 amount,
    IERC20Extended poolDepositAsset,
    uint256 expectedLiquidityMinted,
    bool customCooldown
  ) private returns (uint256 liquidityMinted) {
    // Sweep fee to sink
    uint256 fee = getFee(pool, amount);
    if (fee > 0 && customCooldown) {
      depositAsset.transfer(feeSink, fee);
    }

    if (depositAsset != poolDepositAsset) {
      EasySwapperSwap.swapThat(withdrawProps.swapRouter, depositAsset, poolDepositAsset);
    }

    // Approve the pool to take the funds
    poolDepositAsset.approve(address(pool), poolDepositAsset.balanceOf(address(this)));

    if (customCooldown) {
      liquidityMinted = IPoolLogic(pool).depositForWithCustomCooldown(
        msg.sender,
        address(poolDepositAsset),
        poolDepositAsset.balanceOf(address(this)),
        15 minutes
      );
    } else {
      liquidityMinted = IPoolLogic(pool).depositFor(
        msg.sender,
        address(poolDepositAsset),
        poolDepositAsset.balanceOf(address(this))
      );
    }
    require(liquidityMinted >= expectedLiquidityMinted, "slippage");

    emit Deposit(pool, msg.sender, address(depositAsset), amount, address(poolDepositAsset), liquidityMinted);
  }

  /// @notice calculates the fee based on the settings
  /// @dev fee bypass is for cases like Toros pool manager wants to buy other Toros products (dSNX has USDy)
  /// @param pool the pool to check
  /// @param amount the net amount
  function getFee(address pool, uint256 amount) internal view returns (uint256 fee) {
    if (feeNumerator > 0 && feeDenominator > 0 && feeSink != address(0)) {
      fee = amount.mul(feeNumerator).div(feeDenominator);
    }

    IPoolLogic poolLogic = IPoolLogic(pool);
    (, , uint256 entryFeeNumerator, ) = IPoolManagerLogic(poolLogic.poolManagerLogic()).getFee();
    // Do not charge Swapper's fee if the pool has an entry fee set
    if (entryFeeNumerator > 0) {
      fee = 0;
    }

    // Fee bypass
    if (IPoolFactory(poolLogic.factory()).isPool(msg.sender)) {
      IManaged poolManagerLogic = IManaged(IPoolLogic(msg.sender).poolManagerLogic());
      address manager = poolManagerLogic.manager();
      if (managerFeeBypass[manager]) {
        fee = 0;
      }
    }
  }

  /// @notice calculates how many tokens the user should receive on deposit based on current swap conditions
  /// @param pool the pool to deposit into
  /// @param depositAsset the asset the user wants to deposit
  /// @param amount the amount of the deposit asset
  /// @param poolDepositAsset the asset that the pool accepts
  /// @param customCooldown quote required for custom cooldown deposit method or not
  /// @return expectedLiquidityMinted the expected amount of pool tokens to receive inclusive of slippage
  function depositQuote(
    address pool,
    IERC20Extended depositAsset,
    uint256 amount,
    IERC20Extended poolDepositAsset,
    bool customCooldown
  ) external view returns (uint256 expectedLiquidityMinted) {
    uint256 tokenPrice = IPoolLogic(pool).tokenPrice();
    uint256 depositAmount = amount;
    if (customCooldown) {
      depositAmount = depositAmount - getFee(pool, amount);
    }

    if (depositAsset != poolDepositAsset) {
      address[] memory path = new address[](2);
      path[0] = address(depositAsset);
      path[1] = address(poolDepositAsset);
      uint256[] memory amountsOut = withdrawProps.swapRouter.getAmountsOut(depositAmount, path);
      depositAmount = amountsOut[amountsOut.length - 1];
    }
    IPoolManagerLogic managerLogic = IPoolManagerLogic(IPoolLogic(pool).poolManagerLogic());
    uint256 depositValue = managerLogic.assetValue(address(poolDepositAsset), depositAmount);

    if (tokenPrice == 0) {
      expectedLiquidityMinted = depositValue;
    } else {
      expectedLiquidityMinted = depositValue.mul(10 ** 18).div(tokenPrice);
    }

    (, , uint256 entryFeeNumerator, uint256 denominator) = managerLogic.getFee();
    if (entryFeeNumerator > 0) {
      expectedLiquidityMinted = expectedLiquidityMinted.mul(denominator.sub(entryFeeNumerator)).div(denominator);
    }
  }

  /// @notice withdraw underlying value of tokens in expectedWithdrawalAssetOfUser
  /// @dev Swaps the underlying pool withdrawal assets to expectedWithdrawalAssetOfUser
  /// @param pool dhedgepool to withdraw from
  /// @param fundTokenAmount the amount to withdraw
  /// @param withdrawalAsset must have direct pair to all pool.supportedAssets on swapRouter
  /// @param expectedAmountOut the amount of value in the withdrawalAsset expected (slippage protection)
  function withdraw(
    address pool,
    uint256 fundTokenAmount,
    IERC20Extended withdrawalAsset,
    uint256 expectedAmountOut
  ) external {
    IERC20Extended(pool).transferFrom(msg.sender, address(this), fundTokenAmount);
    EasySwapperWithdrawer.withdraw(
      msg.sender,
      pool,
      fundTokenAmount,
      withdrawalAsset,
      expectedAmountOut,
      withdrawProps
    );
  }

  /// @notice Withdraw underlying value of tokens into intermediate asset and then swap to susd
  /// @dev Helper function for dsnx
  /// @param pool dhedgepool to withdraw from
  /// @param fundTokenAmount the dhedgepool amount to withdraw
  /// @param intermediateAsset must have direct pair to all pool.supportedAssets on swapRouter and to SUSD
  /// @param expectedAmountSUSD the amount of value in susd expected (slippage protection)
  function withdrawSUSD(
    address pool,
    uint256 fundTokenAmount,
    IERC20Extended intermediateAsset,
    uint256 expectedAmountSUSD
  ) external {
    withdrawIntermediate(
      pool,
      fundTokenAmount,
      intermediateAsset,
      IERC20Extended(address(withdrawProps.synthetixProps.sUSDProxy)),
      expectedAmountSUSD
    );
  }

  /// @notice Withdraw underlying value of tokens into intermediate asset and then swap to final asset
  /// @param pool dhedgepool to withdraw from
  /// @param fundTokenAmount the dhedgepool amount to withdraw
  /// @param intermediateAsset must have direct pair to all pool.supportedAssets on swapRouter
  /// @param finalAsset must have direct pair to intermediate asset
  /// @param expectedAmountFinalAsset the amount of value in final asset expected (slippage protection)
  function withdrawIntermediate(
    address pool,
    uint256 fundTokenAmount,
    IERC20Extended intermediateAsset,
    IERC20Extended finalAsset,
    uint256 expectedAmountFinalAsset
  ) public {
    IERC20Extended(pool).transferFrom(msg.sender, address(this), fundTokenAmount);
    EasySwapperWithdrawer.withdrawWithIntermediate(
      msg.sender,
      pool,
      fundTokenAmount,
      intermediateAsset,
      finalAsset,
      expectedAmountFinalAsset,
      withdrawProps
    );
  }
}
