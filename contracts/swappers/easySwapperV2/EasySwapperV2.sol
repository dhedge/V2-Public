// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import {SafeERC20} from "../../utils/SafeERC20.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

import {ISwapper} from "../../interfaces/flatMoney/swapper/ISwapper.sol";
import {IEasySwapperV2} from "./interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "./interfaces/IWithdrawalVault.sol";
import {IPoolFactory} from "../../interfaces/IPoolFactory.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {VaultProxyFactory} from "./VaultProxyFactory.sol";

/// @author dHEDGE team
contract EasySwapperV2 is VaultProxyFactory, IEasySwapperV2 {
  using SafeERC20 for IERC20;
  using SafeMathUpgradeable for uint256;

  struct WhitelistSetting {
    address toWhitelist;
    bool whitelisted;
  }

  struct SingleInSingleOutData {
    ISwapper.SrcTokenSwapDetails srcData;
    ISwapper.DestData destData;
  }

  enum WithdrawalVaultType {
    SINGLE_ASSET_WITHDRAWAL,
    LIMIT_ORDER
  }

  uint256 public constant DEFAULT_COOLDOWN = 1 days;

  /// @notice Deprecated
  address public weth;

  /// @notice Encapsulates offchain swaps logic
  ISwapper public override swapper;

  /// @notice WETH address (or WMATIC address if Polygon)
  IWETH public wrappedNativeToken;

  /// @notice Lowered lockup time after deposit
  uint256 public customCooldown;

  /// @notice Stores Depositor => WithdrawalVault 1 to 1 relationship
  mapping(address => address) public override withdrawalContracts;

  /// @notice Stores dHEDGE vault adresses which are whitelisted for lower lockup time after deposit
  mapping(address => bool) public customCooldownDepositsWhitelist;

  address public dHedgePoolFactory;

  /// @notice Stores addresses which are allowed to call the `completeLimitOrderWithdrawalFor` function
  mapping(address => bool) public isAuthorizedWithdrawer;

  /// Stores Depositor => WithdrawalVault 1 to 1 relationship
  mapping(address => address) public override limitOrderContracts;

  event ZapDepositCompleted(
    address indexed depositor,
    address indexed dHedgeVault,
    IERC20 vaultDepositToken,
    IERC20 userDepositToken,
    uint256 amountReceived,
    uint256 lockupTime
  );
  event WithdrawalInitiated(
    address withdrawalVault,
    address indexed depositor,
    address dHedgeVault,
    uint256 amountWithdrawn
  );
  event WithdrawalCompleted(address withdrawalVault, address indexed depositor);
  event WithdrawalVaultCreated(address withdrawalVault, address indexed depositor);
  event LimitOrderVaultCreated(address limitOrderVault, address indexed depositor);
  event AuthorizedWithdrawersSet(WhitelistSetting[] whitelistSettings);

  /// @notice Reverts if vault can not be deposited into with custom lockup time
  /// @dev Entry fee bigger than 0.1% is a must during custom (lower) lockup time during deposit
  modifier isCustomCooldownAllowed(address _dHedgeVault) {
    require(customCooldownDepositsWhitelist[_dHedgeVault], "not whitelisted");

    (, , uint256 entryFeeNumerator, , ) = IPoolManagerLogic(IPoolLogic(_dHedgeVault).poolManagerLogic()).getFee();
    require(entryFeeNumerator >= 10, "entry fee not set");

    _;
  }

  modifier onlyAuthorizedWithdrawers(address _caller) {
    require(isAuthorizedWithdrawer[_caller], "not authorized");

    _;
  }

  /// @param _vaultLogic WithdrawalVault address implementation
  /// @param _weth WETH address
  /// @param _wrappedNativeToken Wrapped native token address
  /// @param _swapper Swapper contract address
  /// @param _customCooldown Lockup time in seconds
  function initialize(
    address _vaultLogic,
    address _weth,
    IWETH _wrappedNativeToken,
    ISwapper _swapper,
    uint256 _customCooldown
  ) external initializer {
    require(_weth != address(0) && address(_wrappedNativeToken) != address(0), "invalid address");

    __VaultProxyFactory_init(_vaultLogic);

    weth = _weth;
    wrappedNativeToken = _wrappedNativeToken;
    _setSwapper(_swapper);
    _setCustomCooldown(_customCooldown);
  }

  /**
   ***************************************
   *        Regular Deposit Functions    *
   ***************************************
   */

  /// @notice Deposit with any token - receive vault tokens with normal lockup
  ///         Usecase: when deposit token is not among vault's deposit assets
  /// @dev Destination token in swapData struct must be one of vault's deposit assets
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _swapData The struct containing srcData and destData
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  function zapDeposit(
    address _dHedgeVault,
    SingleInSingleOutData calldata _swapData,
    uint256 _expectedAmountReceived
  ) external {
    _swapData.srcData.token.safeTransferFrom(msg.sender, address(this), _swapData.srcData.amount);

    _zapDeposit(_dHedgeVault, _swapData, _expectedAmountReceived, DEFAULT_COOLDOWN);
  }

  /// @notice Deposit with any token - receive vault tokens with lowered lockup
  ///         Usecase: Lowered lockup required (e.g. leverage vaults)
  ///                  Deposit into vault from within vault
  /// @dev Destination token in swapData struct must be one of vault's deposit assets
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _swapData The struct containing srcData and destData
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  function zapDepositWithCustomCooldown(
    address _dHedgeVault,
    SingleInSingleOutData calldata _swapData,
    uint256 _expectedAmountReceived
  ) external isCustomCooldownAllowed(_dHedgeVault) {
    _swapData.srcData.token.safeTransferFrom(msg.sender, address(this), _swapData.srcData.amount);

    _zapDeposit(_dHedgeVault, _swapData, _expectedAmountReceived, customCooldown);
  }

  /// @notice Deposit with token which is accepted by vault - receive vault tokens with normal lockup
  ///         Usecase: simplify deposit logic on the UI. Use this wrapper instead of depositing through core contract
  /// @dev Doesn't perform any swaps, simply wraps PoolLogic::deposit function
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _vaultDepositToken dHEDGE vault's deposit token
  /// @param _depositAmount Amount of dHEDGE vault deposit token to deposit
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  function deposit(
    address _dHedgeVault,
    IERC20 _vaultDepositToken,
    uint256 _depositAmount,
    uint256 _expectedAmountReceived
  ) external {
    _deposit(_dHedgeVault, _vaultDepositToken, _depositAmount, _expectedAmountReceived, DEFAULT_COOLDOWN);
  }

  /// @notice Deposit with token which is accepted by vault - receive vault tokens with lowered lockup
  ///         Usecase: Lowered lockup required (e.g. leverage vaults)
  ///                  Deposit into vault from within vault
  /// @dev Doesn't perform any swaps, simply wraps PoolLogic::deposit function
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _vaultDepositToken dHEDGE vault's deposit token
  /// @param _depositAmount Amount of dHEDGE vault deposit token to deposit
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  function depositWithCustomCooldown(
    address _dHedgeVault,
    IERC20 _vaultDepositToken,
    uint256 _depositAmount,
    uint256 _expectedAmountReceived
  ) external isCustomCooldownAllowed(_dHedgeVault) {
    _deposit(_dHedgeVault, _vaultDepositToken, _depositAmount, _expectedAmountReceived, customCooldown);
  }

  /**
   ***************************************
   *        Native Deposit Functions     *
   ***************************************
   */

  /// @notice Deposit with native token - receive vault tokens with normal lockup
  ///         Usecase: native deposit when native token wrapper is not among vault's deposit assets
  /// @dev Source token in swapData struct must be wrapped native token
  ///      Destination token in swapData struct must be one of vault's deposit assets
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _swapData The struct containing srcData and destData
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  function zapNativeDeposit(
    address _dHedgeVault,
    SingleInSingleOutData calldata _swapData,
    uint256 _expectedAmountReceived
  ) external payable {
    _zapNativeDeposit(_dHedgeVault, _swapData, _expectedAmountReceived, DEFAULT_COOLDOWN);
  }

  /// @notice Deposit with native token - receive vault tokens with lowered lockup
  ///         Usecase: native deposit when lowered lockup required (e.g. leverage vaults), when native token wrapper is not among vault's deposit assets
  /// @dev Source token in swapData struct must be wrapped native token
  ///      Destination token in swapData struct must be one of vault's deposit assets
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _swapData The struct containing srcData and destData
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  function zapNativeDepositWithCustomCooldown(
    address _dHedgeVault,
    SingleInSingleOutData calldata _swapData,
    uint256 _expectedAmountReceived
  ) external payable isCustomCooldownAllowed(_dHedgeVault) {
    _zapNativeDeposit(_dHedgeVault, _swapData, _expectedAmountReceived, customCooldown);
  }

  /// @notice Deposit with native token - receive vault tokens with normal lockup
  ///         Usecase: native deposit when native token wrapper is AMONG vault's deposit assets
  /// @dev Doesn't perform any swaps, simply wraps native token and deposits
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  function nativeDeposit(address _dHedgeVault, uint256 _expectedAmountReceived) external payable {
    _nativeDeposit(_dHedgeVault, _expectedAmountReceived, DEFAULT_COOLDOWN);
  }

  /// @notice Deposit with native token - receive vault tokens with lowered lockup
  ///         Usecase: native deposit when lowered lockup required (e.g. leverage vaults), when native token wrapper is AMONG vault's deposit assets
  /// @dev Doesn't perform any swaps, simply wraps native token and deposits
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  function nativeDepositWithCustomCooldown(
    address _dHedgeVault,
    uint256 _expectedAmountReceived
  ) external payable isCustomCooldownAllowed(_dHedgeVault) {
    _nativeDeposit(_dHedgeVault, _expectedAmountReceived, customCooldown);
  }

  /**
   ***************************************
   *        Withdrawal Functions         *
   ***************************************
   */

  /// @notice First of two-step withdrawal process
  /// @dev Need to allow EasySwapperV2 to spend dHEDGE Vault tokens
  /// @param _dHedgeVault dHEDGE Vault address
  /// @param _amountIn Amount of dHEDGE Vault tokens to withdraw
  /// @param _complexAssetsData See PoolLogic::withdrawToSafe
  /// @return trackedAssets full array of basic assets and their balances
  /// @return vault Address of the WithdrawalVault for the msg.sender
  function initWithdrawal(
    address _dHedgeVault,
    uint256 _amountIn,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData
  ) public returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) {
    return
      _initWithdrawalFor(
        msg.sender,
        _dHedgeVault,
        _amountIn,
        _complexAssetsData,
        WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL
      );
  }

  /// @notice Function to be called by contract managing limit orders
  /// @dev Need to allow EasySwapperV2 to spend dHEDGE Vault tokens
  /// @param _user Address of the depositor
  /// @param _dHedgeVault dHEDGE Vault address
  /// @param _amountIn Amount of dHEDGE Vault tokens to withdraw
  /// @param _complexAssetsData See PoolLogic::withdrawToSafe
  /// @return trackedAssets full array of basic assets and their balances
  /// @return vault Address of the WithdrawalVault for the _user
  function initLimitOrderWithdrawalFor(
    address _user,
    address _dHedgeVault,
    uint256 _amountIn,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData
  ) external override returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) {
    return _initWithdrawalFor(_user, _dHedgeVault, _amountIn, _complexAssetsData, WithdrawalVaultType.LIMIT_ORDER);
  }

  /// @notice Second of two-step withdrawal process
  /// @dev Allows receiving single asset for withdrawal initiated during first step, requires swap data
  /// @param _swapData Encapsulates offchain swaps logic
  /// @param _expectedDestTokenAmount Expected amount of destination token to receive
  function completeWithdrawal(
    IWithdrawalVault.MultiInSingleOutData calldata _swapData,
    uint256 _expectedDestTokenAmount
  ) external returns (uint256 destTokenAmount) {
    return
      _completeWithdrawal(msg.sender, _swapData, _expectedDestTokenAmount, WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL);
  }

  /// @notice Second of two-step withdrawal process
  /// @dev Allows receiving multiple assets for withdrawal initiated during first step, doesn't swap anything
  function completeWithdrawal() external {
    _claimTokensFromVault(msg.sender, WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL);
  }

  /// @notice Completes a limit order withdrawal by claiming tokens directly from the vault
  /// @dev Simpler version that just claims tokens without any swapping
  function completeLimitOrderWithdrawal() external {
    completeLimitOrderWithdrawalFor(msg.sender);
  }

  /// @notice Only callable by authorized withdrawers (trusted keepers).
  /// @dev Allows receiving single asset for withdrawal initiated during first step and requires swap data.
  /// @param _user Address of the depositor
  /// @param _swapData Encapsulates offchain swaps logic
  /// @param _expectedDestTokenAmount Expected amount of destination token to receive
  function completeLimitOrderWithdrawalFor(
    address _user,
    IWithdrawalVault.MultiInSingleOutData calldata _swapData,
    uint256 _expectedDestTokenAmount
  ) external override onlyAuthorizedWithdrawers(msg.sender) returns (uint256 destTokenAmount) {
    return _completeWithdrawal(_user, _swapData, _expectedDestTokenAmount, WithdrawalVaultType.LIMIT_ORDER);
  }

  /// @notice Anyone can call and send tokens to user from their vault
  /// @param _user Address of the depositor
  function completeLimitOrderWithdrawalFor(address _user) public {
    _claimTokensFromVault(_user, WithdrawalVaultType.LIMIT_ORDER);
  }

  /// @dev To be used by PoolLogic during withdrawProcessing
  function partialWithdraw(uint256 _portion, address _to) external override {
    require(_portion > 0 && _portion <= 1e18, "invalid portion");

    address withdrawalVault = _getVault(msg.sender, WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL);
    IWithdrawalVault(withdrawalVault).recoverAssets(_portion, _to);

    emit WithdrawalCompleted(withdrawalVault, msg.sender);
  }

  /// @notice Can be used instead initWithdrawal + completeWithdrawal() without swap to withdraw in a single step
  /// @param _dHedgeVault dHEDGE Vault address
  /// @param _amountIn Amount of dHEDGE Vault tokens to withdraw
  /// @param _complexAssetsData See PoolLogic::withdrawToSafe
  /// @return trackedAssets full array of basic assets and their balances
  function unrollAndClaim(
    address _dHedgeVault,
    uint256 _amountIn,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData
  ) external returns (IWithdrawalVault.TrackedAsset[] memory) {
    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = initWithdrawal(
      _dHedgeVault,
      _amountIn,
      _complexAssetsData
    );

    IWithdrawalVault(vault).recoverAssets();

    emit WithdrawalCompleted(vault, msg.sender);

    return trackedAssets;
  }

  /**
   ***************************************
   *        View Functions               *
   ***************************************
   */

  /// @notice Calculate expected amount of vault tokens received from deposit
  /// @param _dHedgeVault dHEDGE Vault address
  /// @param _vaultDepositToken dHEDGE vault's deposit token
  /// @param _depositAmount Amount of deposit token
  /// @return expectedAmountReceived Expected amount of vault tokens
  function depositQuote(
    address _dHedgeVault,
    address _vaultDepositToken,
    uint256 _depositAmount
  ) external view returns (uint256 expectedAmountReceived) {
    uint256 tokenPrice = IPoolLogic(_dHedgeVault).tokenPrice();
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(IPoolLogic(_dHedgeVault).poolManagerLogic());
    uint256 depositValue = poolManagerLogic.assetValue(_vaultDepositToken, _depositAmount);

    if (tokenPrice == 0) {
      expectedAmountReceived = depositValue;
    } else {
      expectedAmountReceived = depositValue.mul(1e18).div(tokenPrice);
    }

    (, , uint256 entryFeeNumerator, , uint256 denominator) = poolManagerLogic.getFee();
    if (entryFeeNumerator > 0) {
      uint256 entryFee = expectedAmountReceived.mul(entryFeeNumerator).div(denominator);
      expectedAmountReceived = expectedAmountReceived.sub(entryFee);
    }
  }

  /// @notice For client code to know which assets are available for swapping
  /// @param _depositor Address of the depositor
  /// @return trackedAssets full array of basic assets and their balances
  function getTrackedAssets(
    address _depositor
  ) external view override returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets) {
    return _getTrackedAssets(_depositor, WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL);
  }

  /// @notice For client code to know which assets are available for swapping
  /// @param _depositor Address of the depositor
  /// @return trackedAssets full array of basic assets and their balances
  function getTrackedAssetsFromLimitOrders(
    address _depositor
  ) external view override returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets) {
    return _getTrackedAssets(_depositor, WithdrawalVaultType.LIMIT_ORDER);
  }

  /// @notice Check if provided address is a dHEDGE vault
  /// @param _dHedgeVault Address to check
  function isdHedgeVault(address _dHedgeVault) public view override returns (bool isVault) {
    isVault = IPoolFactory(dHedgePoolFactory).isPool(_dHedgeVault);
  }

  /**
   ***************************************
   *        Owner Functions              *
   ***************************************
   */

  /// @notice Setter to add/remove dHEDGE vaults to/from custom cooldown whitelist
  /// @param _whitelistSettings Array of dHEDGE vaults with whitelist status
  function setCustomCooldownWhitelist(WhitelistSetting[] calldata _whitelistSettings) external onlyOwner {
    for (uint256 i; i < _whitelistSettings.length; ++i) {
      require(isdHedgeVault(_whitelistSettings[i].toWhitelist), "not a vault");

      customCooldownDepositsWhitelist[_whitelistSettings[i].toWhitelist] = _whitelistSettings[i].whitelisted;
    }
  }

  /// @notice Setter to set Swapper contract (resides at flat.money contracts)
  /// @param _swapper New swapper address
  function setSwapper(ISwapper _swapper) external onlyOwner {
    _setSwapper(_swapper);
  }

  /// @notice Setter to change custom cooldown, if needed
  /// @param _customCooldown New custom cooldown
  function setCustomCooldown(uint256 _customCooldown) external onlyOwner {
    _setCustomCooldown(_customCooldown);
  }

  /// @notice Setter to set dHEDGE Pool Factory
  /// @param _dHedgePoolFactory dHEDGE Pool Factory contract address
  function setdHedgePoolFactory(address _dHedgePoolFactory) external onlyOwner {
    require(_dHedgePoolFactory != address(0), "invalid address");

    dHedgePoolFactory = _dHedgePoolFactory;
  }

  function setAuthorizedWithdrawers(WhitelistSetting[] calldata _whitelistSettings) external onlyOwner {
    for (uint256 i; i < _whitelistSettings.length; ++i) {
      isAuthorizedWithdrawer[_whitelistSettings[i].toWhitelist] = _whitelistSettings[i].whitelisted;
    }

    emit AuthorizedWithdrawersSet(_whitelistSettings);
  }

  /**
   ***************************************
   *        Internal and Private         *
   ***************************************
   */

  /// @param _swapper New swapper address
  function _setSwapper(ISwapper _swapper) internal {
    require(address(_swapper) != address(0), "invalid address");

    swapper = _swapper;
  }

  /// @param _customCooldown New custom cooldown
  function _setCustomCooldown(uint256 _customCooldown) internal {
    require(_customCooldown >= 5 minutes && _customCooldown <= DEFAULT_COOLDOWN, "invalid custom cooldown");

    customCooldown = _customCooldown;
  }

  function _deployVault(address _depositor, WithdrawalVaultType _type) internal returns (address vault) {
    bytes memory initVaultData = abi.encodeWithSignature("initialize(address,address)", _depositor, address(this));

    vault = _deploy(initVaultData);

    if (_type == WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL) {
      withdrawalContracts[_depositor] = vault;

      emit WithdrawalVaultCreated(vault, _depositor);
    } else {
      limitOrderContracts[_depositor] = vault;

      emit LimitOrderVaultCreated(vault, _depositor);
    }
  }

  /// @notice Wraps native token before zapping into dHEDGE vault
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _swapData The struct containing srcData and destData
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  /// @param _cooldown Cooldown time in seconds
  function _zapNativeDeposit(
    address _dHedgeVault,
    SingleInSingleOutData calldata _swapData,
    uint256 _expectedAmountReceived,
    uint256 _cooldown
  ) internal {
    require(address(_swapData.srcData.token) == address(wrappedNativeToken), "invalid src token");

    require(_swapData.srcData.amount == msg.value, "invalid src amount");

    wrappedNativeToken.deposit{value: msg.value}();

    _zapDeposit(_dHedgeVault, _swapData, _expectedAmountReceived, _cooldown);
  }

  /// @notice Swaps src token into dest token before depositing into dHEDGE vault
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _swapData The struct containing srcData and destData
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  /// @param _cooldown Cooldown time in seconds
  function _zapDeposit(
    address _dHedgeVault,
    SingleInSingleOutData calldata _swapData,
    uint256 _expectedAmountReceived,
    uint256 _cooldown
  ) internal {
    uint256 vaultDepositTokenBalanceBefore = _swapData.destData.destToken.balanceOf(address(this));

    _swapData.srcData.token.safeIncreaseAllowance(address(swapper), _swapData.srcData.amount);

    ISwapper.InOutData memory swapProps;
    ISwapper.SrcData[] memory srcData = new ISwapper.SrcData[](1);
    ISwapper.SrcTokenSwapDetails[] memory srcTokenSwapDetails = new ISwapper.SrcTokenSwapDetails[](1);
    srcTokenSwapDetails[0].token = _swapData.srcData.token;
    srcTokenSwapDetails[0].amount = _swapData.srcData.amount;
    srcTokenSwapDetails[0].aggregatorData = _swapData.srcData.aggregatorData;
    srcData[0].srcTokenSwapDetails = srcTokenSwapDetails;
    srcData[0].transferMethodData.method = ISwapper.TransferMethod.ALLOWANCE;
    swapProps.srcData = srcData;
    swapProps.destData = _swapData.destData;

    swapper.swap(swapProps);

    uint256 vaultDepositTokenReceived = _swapData.destData.destToken.balanceOf(address(this)).sub(
      vaultDepositTokenBalanceBefore
    );

    _swapData.destData.destToken.safeIncreaseAllowance(_dHedgeVault, vaultDepositTokenReceived);

    uint256 amountReceived = IPoolLogic(_dHedgeVault).depositForWithCustomCooldown(
      msg.sender,
      address(_swapData.destData.destToken),
      vaultDepositTokenReceived,
      _cooldown
    );

    require(amountReceived >= _expectedAmountReceived, "high deposit slippage");

    emit ZapDepositCompleted({
      depositor: msg.sender,
      dHedgeVault: _dHedgeVault,
      vaultDepositToken: _swapData.destData.destToken,
      userDepositToken: _swapData.srcData.token,
      amountReceived: amountReceived,
      lockupTime: _cooldown
    });
  }

  /// @notice Wraps native token before depositing into dHEDGE vault
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  /// @param _cooldown Cooldown time in seconds
  function _nativeDeposit(address _dHedgeVault, uint256 _expectedAmountReceived, uint256 _cooldown) internal {
    wrappedNativeToken.deposit{value: msg.value}();

    IERC20(address(wrappedNativeToken)).safeIncreaseAllowance(_dHedgeVault, msg.value);

    uint256 amountReceived = IPoolLogic(_dHedgeVault).depositForWithCustomCooldown(
      msg.sender,
      address(wrappedNativeToken),
      msg.value,
      _cooldown
    );

    require(amountReceived >= _expectedAmountReceived, "high deposit slippage");
  }

  /// @notice Deposits into dHEDGE vault
  /// @param _dHedgeVault dHEDGE vault address
  /// @param _vaultDepositToken dHEDGE vault's deposit token
  /// @param _depositAmount Amount of dHEDGE vault deposit token to deposit
  /// @param _expectedAmountReceived Expected amount of dHEDGE vault tokens received
  /// @param _cooldown Cooldown time in seconds
  function _deposit(
    address _dHedgeVault,
    IERC20 _vaultDepositToken,
    uint256 _depositAmount,
    uint256 _expectedAmountReceived,
    uint256 _cooldown
  ) internal {
    _vaultDepositToken.safeTransferFrom(msg.sender, address(this), _depositAmount);

    _vaultDepositToken.safeIncreaseAllowance(_dHedgeVault, _depositAmount);

    uint256 amountReceived = IPoolLogic(_dHedgeVault).depositForWithCustomCooldown(
      msg.sender,
      address(_vaultDepositToken),
      _depositAmount,
      _cooldown
    );

    require(amountReceived >= _expectedAmountReceived, "high deposit slippage");
  }

  function _initWithdrawalFor(
    address _user,
    address _dHedgeVault,
    uint256 _amountIn,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData,
    WithdrawalVaultType _type
  ) internal returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) {
    require(isdHedgeVault(_dHedgeVault), "not a vault");

    IERC20(_dHedgeVault).safeTransferFrom(msg.sender, address(this), _amountIn);

    vault = _selectWithdrawalVault(_user, _type);

    IPoolLogic(_dHedgeVault).withdrawToSafe(vault, _amountIn, _complexAssetsData);

    IWithdrawalVault(vault).unrollAssets(_dHedgeVault);

    trackedAssets = IWithdrawalVault(vault).getTrackedAssets();

    emit WithdrawalInitiated({
      withdrawalVault: vault,
      depositor: _user,
      dHedgeVault: _dHedgeVault,
      amountWithdrawn: _amountIn
    });
  }

  function _completeWithdrawal(
    address _user,
    IWithdrawalVault.MultiInSingleOutData calldata _swapData,
    uint256 _expectedDestTokenAmount,
    WithdrawalVaultType _vaultType
  ) internal returns (uint256 destTokenAmount) {
    address vault = _getVault(_user, _vaultType);
    destTokenAmount = IWithdrawalVault(vault).swapToSingleAsset(_swapData, _expectedDestTokenAmount);

    emit WithdrawalCompleted(vault, _user);
  }

  function _claimTokensFromVault(address _user, WithdrawalVaultType _vaultType) internal {
    address vault = _getVault(_user, _vaultType);
    IWithdrawalVault(vault).recoverAssets();

    emit WithdrawalCompleted(vault, _user);
  }

  /// @dev Creates a new vault if it doesn't exist
  function _selectWithdrawalVault(address _user, WithdrawalVaultType _type) internal returns (address vault) {
    if (_type == WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL) {
      vault = withdrawalContracts[_user];
    } else {
      vault = limitOrderContracts[_user];
    }

    if (vault == address(0)) vault = _deployVault(_user, _type);
  }

  /// @dev Returns address(0) if no vault exists for the user
  function _getVaultSafe(address _depositor, WithdrawalVaultType _type) internal view returns (address vault) {
    if (_type == WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL) {
      vault = withdrawalContracts[_depositor];
    } else {
      vault = limitOrderContracts[_depositor];
    }
  }

  /// @dev Reverts if no vault exists for the user
  function _getVault(address _depositor, WithdrawalVaultType _type) internal view returns (address vault) {
    vault = _getVaultSafe(_depositor, _type);

    require(vault != address(0), "not exists");
  }

  function _getTrackedAssets(
    address _depositor,
    WithdrawalVaultType _type
  ) internal view returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets) {
    address vault = _getVaultSafe(_depositor, _type);

    if (vault == address(0)) {
      return trackedAssets;
    }

    return IWithdrawalVault(vault).getTrackedAssets();
  }
}
