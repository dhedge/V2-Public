// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

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

  struct CustomCooldownSetting {
    address dHedgeVault;
    bool whitelisted;
  }

  struct SingleInSingleOutData {
    ISwapper.SrcTokenSwapDetails srcData;
    ISwapper.DestData destData;
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

  /// @notice Reverts if there is no vault to complete withdrawal from
  modifier checkVaultExistence(address _depositor) {
    require(withdrawalContracts[_depositor] != address(0), "not exists");
    _;
  }

  /// @notice Reverts if vault can not be deposited into with custom lockup time
  /// @dev Entry fee bigger than 0.1% is a must during custom (lower) lockup time during deposit
  modifier isCustomCooldownAllowed(address _dHedgeVault) {
    require(customCooldownDepositsWhitelist[_dHedgeVault], "not whitelisted");

    (, , uint256 entryFeeNumerator, , ) = IPoolManagerLogic(IPoolLogic(_dHedgeVault).poolManagerLogic()).getFee();
    require(entryFeeNumerator >= 10, "entry fee not set");

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
  /// @dev Doesn't perform any swaps, simply wraps PoolLogic's deposit function
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
  /// @dev Doesn't perform any swaps, simply wraps PoolLogic's deposit function
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
  /// @param _slippageTolerance Slippage tolerance for withdrawal, see PoolLogic's withdrawToSafe function
  /// @return trackedAssets full array of basic assets and their balances
  /// @return vault Address of the WithdrawalVault for the msg.sender
  function initWithdrawal(
    address _dHedgeVault,
    uint256 _amountIn,
    uint256 _slippageTolerance
  ) public returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) {
    require(isdHedgeVault(_dHedgeVault), "not a vault");

    IERC20(_dHedgeVault).safeTransferFrom(msg.sender, address(this), _amountIn);

    vault = withdrawalContracts[msg.sender];
    if (vault == address(0)) {
      vault = _createWithdrawalVault(msg.sender);
    }

    IPoolLogic(_dHedgeVault).withdrawToSafe(vault, _amountIn, _slippageTolerance);

    IWithdrawalVault(vault).unrollAssets(_dHedgeVault, _slippageTolerance);

    trackedAssets = IWithdrawalVault(vault).getTrackedAssets();

    emit WithdrawalInitiated({
      withdrawalVault: vault,
      depositor: msg.sender,
      dHedgeVault: _dHedgeVault,
      amountWithdrawn: _amountIn
    });
  }

  /// @notice Second of two-step withdrawal process
  /// @dev Allows receiving single asset for withdrawal initiated during first step, requires swap data
  /// @param _swapData Encapsulates offchain swaps logic
  /// @param _expectedDestTokenAmount Expected amount of destination token to receive
  function completeWithdrawal(
    IWithdrawalVault.MultiInSingleOutData calldata _swapData,
    uint256 _expectedDestTokenAmount
  ) external checkVaultExistence(msg.sender) {
    address withdrawalVault = withdrawalContracts[msg.sender];
    IWithdrawalVault(withdrawalVault).swapToSingleAsset(_swapData, _expectedDestTokenAmount);

    emit WithdrawalCompleted(withdrawalVault, msg.sender);
  }

  /// @notice Second of two-step withdrawal process
  /// @dev Allows receiving multiple assets for withdrawal initiated during first step, doesn't swap anything
  function completeWithdrawal() external checkVaultExistence(msg.sender) {
    address withdrawalVault = withdrawalContracts[msg.sender];
    IWithdrawalVault(withdrawalVault).recoverAssets();

    emit WithdrawalCompleted(withdrawalVault, msg.sender);
  }

  /// @dev To be used by PoolLogic during withdrawProcessing
  function partialWithdraw(uint256 _portion, address _to) external override checkVaultExistence(msg.sender) {
    require(_portion > 0 && _portion <= 1e18, "invalid portion");

    address withdrawalVault = withdrawalContracts[msg.sender];
    IWithdrawalVault(withdrawalVault).recoverAssets(_portion, _to);

    emit WithdrawalCompleted(withdrawalVault, msg.sender);
  }

  /// @notice Can be used instead initWithdrawal + completeWithdrawal() without swap to withdraw in a single step
  /// @param _dHedgeVault dHEDGE Vault address
  /// @param _amountIn Amount of dHEDGE Vault tokens to withdraw
  /// @param _slippageTolerance Slippage tolerance for withdrawal, see PoolLogic's withdrawToSafe function
  /// @return trackedAssets full array of basic assets and their balances
  function unrollAndClaim(
    address _dHedgeVault,
    uint256 _amountIn,
    uint256 _slippageTolerance
  ) external returns (IWithdrawalVault.TrackedAsset[] memory) {
    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = initWithdrawal(
      _dHedgeVault,
      _amountIn,
      _slippageTolerance
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
    address withdrawalVault = withdrawalContracts[_depositor];

    if (withdrawalVault == address(0)) {
      return trackedAssets;
    }

    trackedAssets = IWithdrawalVault(withdrawalVault).getTrackedAssets();
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
  function setCustomCooldownWhitelist(CustomCooldownSetting[] calldata _whitelistSettings) external onlyOwner {
    for (uint256 i; i < _whitelistSettings.length; ++i) {
      require(isdHedgeVault(_whitelistSettings[i].dHedgeVault), "not a vault");

      customCooldownDepositsWhitelist[_whitelistSettings[i].dHedgeVault] = _whitelistSettings[i].whitelisted;
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

  /// @param _depositor Address of the depositor
  /// @return vault Address of the new WithdrawalVault
  function _createWithdrawalVault(address _depositor) internal returns (address vault) {
    bytes memory initVaultData = abi.encodeWithSignature("initialize(address,address)", _depositor, address(this));

    vault = _deploy(initVaultData);

    withdrawalContracts[_depositor] = vault;

    emit WithdrawalVaultCreated(vault, _depositor);
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
}
