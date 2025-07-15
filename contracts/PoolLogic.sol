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
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/introspection/IERC165Upgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IFlashLoanReceiver} from "./interfaces/aave/IFlashLoanReceiver.sol";
import {IAaveLendingPoolAssetGuard} from "./interfaces/guards/IAaveLendingPoolAssetGuard.sol";
import {IAssetGuard} from "./interfaces/guards/IAssetGuard.sol";
import {IERC721VerifyingGuard} from "./interfaces/guards/IERC721VerifyingGuard.sol";
import {IGuard} from "./interfaces/guards/IGuard.sol";
import {IComplexAssetGuard} from "./interfaces/guards/IComplexAssetGuard.sol";
import {ITxTrackingGuard} from "./interfaces/guards/ITxTrackingGuard.sol";
import {IGovernance} from "./interfaces/IGovernance.sol";
import {IHasDaoInfo} from "./interfaces/IHasDaoInfo.sol";
import {IHasFeeInfo} from "./interfaces/IHasFeeInfo.sol";
import {IHasGuardInfo} from "./interfaces/IHasGuardInfo.sol";
import {IHasOwnable} from "./interfaces/IHasOwnable.sol";
import {IHasPausable} from "./interfaces/IHasPausable.sol";
import {IHasSupportedAsset} from "./interfaces/IHasSupportedAsset.sol";
import {IManaged} from "./interfaces/IManaged.sol";
import {IPoolFactory} from "./interfaces/IPoolFactory.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "./interfaces/IPoolManagerLogic.sol";
import {AddressHelper} from "./utils/AddressHelper.sol";

/// @notice Logic implementation for pool
contract PoolLogic is ERC20Upgradeable, ReentrancyGuardUpgradeable, IERC721ReceiverUpgradeable, IFlashLoanReceiver {
  using SafeMathUpgradeable for uint256;
  using AddressHelper for address;

  struct FundSummary {
    string name;
    uint256 totalSupply;
    uint256 totalFundValue;
    address manager;
    string managerName;
    uint256 creationTime;
    bool privatePool;
    uint256 performanceFeeNumerator;
    uint256 managerFeeNumerator;
    uint256 managerFeeDenominator;
    uint256 exitFeeNumerator;
    uint256 exitFeeDenominator;
    uint256 entryFeeNumerator;
  }

  struct TxToExecute {
    address to;
    bytes data;
  }

  struct WithdrawnAsset {
    address asset;
    uint256 amount;
    bool externalWithdrawProcessed;
  }

  /// @dev For stack too deep error
  struct WithdrawProcessing {
    uint256 portionBalance;
    uint256 expectedWithdrawValue;
    bool regularProcessingUsed;
    address guard;
  }

  /// @dev For stack too deep error
  struct WithdrawExecution {
    uint256 supplyAfterBurn;
    uint256 fundValue;
    uint256 feesMinted;
  }

  event Deposit(
    address fundAddress,
    address investor,
    address assetDeposited,
    uint256 amountDeposited,
    uint256 valueDeposited,
    uint256 fundTokensReceived,
    uint256 totalInvestorFundTokens,
    uint256 fundValue,
    uint256 totalSupply,
    uint256 time
  );

  event Withdrawal(
    address fundAddress,
    address investor,
    uint256 valueWithdrawn,
    uint256 fundTokensWithdrawn,
    uint256 totalInvestorFundTokens,
    uint256 fundValue,
    uint256 totalSupply,
    WithdrawnAsset[] withdrawnAssets,
    uint256 time
  );

  event TransactionExecuted(address pool, address manager, uint16 transactionType, uint256 time);

  event PoolPrivacyUpdated(bool isPoolPrivate);

  event ManagerFeeMinted(
    address pool,
    address manager,
    uint256 available,
    uint256 daoFee,
    uint256 managerFee,
    uint256 tokenPriceAtLastFeeMint
  );

  event PoolManagerLogicSet(address poolManagerLogic, address from);

  event EntryFeeMinted(address manager, uint256 entryFeeAmount);

  event ExitFeeMinted(address manager, uint256 exitFeeAmount);

  bool public privatePool;

  address public creator;

  uint256 public creationTime;

  address public factory;

  uint256 public tokenPriceAtLastFeeMint;

  mapping(address => uint256) public lastDeposit;

  address public poolManagerLogic;

  mapping(address => uint256) public lastWhitelistTransfer;

  uint256 public lastFeeMintTime;

  mapping(address => uint256) public lastExitCooldown;

  modifier whenNotFactoryPaused() {
    require(!IHasPausable(factory).isPaused(), "contracts paused");
    _;
  }

  modifier whenNotPaused() {
    require(!IHasPausable(factory).pausedPools(address(this)), "pool paused");
    _;
  }

  /// @notice Initialize the pool
  /// @param _factory address of the factory
  /// @param _privatePool true if the pool is private, false otherwise
  /// @param _fundName name of the fund
  /// @param _fundSymbol symbol of the fund
  function initialize(
    address _factory,
    bool _privatePool,
    string memory _fundName,
    string memory _fundSymbol
  ) external initializer {
    __ERC20_init(_fundName, _fundSymbol);
    __ReentrancyGuard_init();

    factory = _factory;
    privatePool = _privatePool;
    creator = msg.sender;
    creationTime = block.timestamp;
    lastFeeMintTime = block.timestamp;
    tokenPriceAtLastFeeMint = 10 ** 18;
  }

  /// @notice Before token transfer hook
  /// @param _from address of the token owner
  /// @param _to address of the token receiver
  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256
  ) internal virtual override whenNotFactoryPaused whenNotPaused {
    // Minting
    if (_from == address(0)) {
      return;
    }

    if (IPoolFactory(factory).receiverWhitelist(_to) == true) {
      return;
    }

    require(getExitRemainingCooldown(_from) == 0, "cooldown active");
  }

  /// @notice Set the pool privacy
  /// @param _privatePool true if the pool is private, false otherwise
  function setPoolPrivate(bool _privatePool) external {
    require(msg.sender == _manager(), "only manager");

    privatePool = _privatePool;

    emit PoolPrivacyUpdated(_privatePool);
    _emitFactoryEvent();
  }

  /// @notice Deposit funds into the pool
  /// @param _asset Address of the token
  /// @param _amount Amount of tokens to deposit
  /// @return liquidityMinted Amount of liquidity minted
  function deposit(address _asset, uint256 _amount) external returns (uint256 liquidityMinted) {
    return _depositFor(msg.sender, _asset, _amount, _exitCooldown());
  }

  /// @notice Deposit funds into the pool for a specific recipient
  /// @dev This function allows the recipient to be different from the sender
  /// @param _recipient Address of the recipient
  /// @param _asset Address of the token
  /// @param _amount Amount of tokens to deposit
  /// @return liquidityMinted Amount of liquidity minted
  function depositFor(address _recipient, address _asset, uint256 _amount) external returns (uint256 liquidityMinted) {
    return _depositFor(_recipient, _asset, _amount, _exitCooldown());
  }

  /// @notice Deposit funds into the pool for a specific recipient with a custom lockup time
  /// @dev This function allows the recipient to be different from the sender and sets a custom lockup time.
  ///      Sender must be authorized by the owner
  /// @param _recipient Address of the recipient
  /// @param _asset Address of the token
  /// @param _amount Amount of tokens to deposit
  /// @param _cooldown Custom lockup time after the deposit
  /// @return liquidityMinted Amount of liquidity minted
  function depositForWithCustomCooldown(
    address _recipient,
    address _asset,
    uint256 _amount,
    uint256 _cooldown
  ) external returns (uint256 liquidityMinted) {
    require(IPoolFactory(factory).customCooldownWhitelist(msg.sender), "only allowed");
    require(_cooldown >= 5 minutes && _cooldown <= _exitCooldown(), "invalid cooldown");

    return _depositFor(_recipient, _asset, _amount, _cooldown);
  }

  function _depositFor(
    address _recipient,
    address _asset,
    uint256 _amount,
    uint256 _cooldown
  ) private nonReentrant whenNotFactoryPaused whenNotPaused returns (uint256 liquidityMinted) {
    address manager = _manager();
    require(_recipient == manager || !privatePool || _isMemberAllowed(_recipient), "only members");

    require(IPoolManagerLogic(poolManagerLogic).isDepositAsset(_asset), "invalid deposit asset");

    // Checks that the `_asset` is not a ERC721 token.
    // As per ERC721 spec, a compliant contract must implement the ERC165 interface.
    // The interface id for IERC721 is 0x80ac58cd as per <https://ethtools.com/interface-database/ERC721>
    // Also, the `supportsInterface` function should only consume at most 30_000 gas as per ERC165 standard.
    {
      // If the asset supports IERC165, then it should not support IERC721.
      (bool success, bytes memory data) = _asset.staticcall{gas: 30_000}(
        abi.encodeWithSelector(IERC165Upgradeable.supportsInterface.selector, bytes4(0x80ac58cd))
      );

      // Either the call to `supportsInterface` should revert or the IERC721 interface should not be supported.
      require(!success || !abi.decode(data, (bool)), "NFTs not supported");
    }

    (uint256 fundValue, ) = _mintManagerFee();

    uint256 totalSupplyBefore = totalSupply();

    _asset.tryAssemblyCall(
      abi.encodeWithSelector(IERC20Upgradeable.transferFrom.selector, msg.sender, address(this), _amount)
    );

    uint256 usdAmount = _assetValue(_asset, _amount);

    // Scoping to avoid stack too deep errors.
    {
      if (totalSupplyBefore > 0) {
        liquidityMinted = usdAmount.mul(totalSupplyBefore).div(fundValue);
      } else {
        liquidityMinted = usdAmount;
      }

      (, , uint256 entryFeeNumerator, , uint256 denominator) = _managerFees();

      if (entryFeeNumerator > 0) {
        uint256 entryFee = liquidityMinted.mul(entryFeeNumerator).div(denominator);

        // Note: From here on, `liquidityMinted` will refer to the fund tokens minted with entry fee accounted for.
        liquidityMinted = liquidityMinted.sub(entryFee);

        _mint(manager, entryFee);

        emit EntryFeeMinted(manager, entryFee);
      }

      // Note: We are making it impossible for someone to mint liquidity < 100_000.
      // This is so that we can mitigate the inflation attack.
      require(liquidityMinted >= 100_000, "invalid liquidityMinted");

      // As the `_mint` function doesn't hand over the execution control to the caller, we can safely
      // call it before calculating cooldown and other effects.
      _mint(_recipient, liquidityMinted);
    }

    lastExitCooldown[_recipient] = _calculateCooldown(
      balanceOf(_recipient),
      liquidityMinted,
      _cooldown,
      lastExitCooldown[_recipient],
      lastDeposit[_recipient],
      block.timestamp
    );
    lastDeposit[_recipient] = block.timestamp;

    uint256 balance = balanceOf(_recipient);
    uint256 fundValueAfter = fundValue.add(usdAmount);

    {
      uint256 totalSupplyAfter = totalSupply();

      require(
        balance.mul(_tokenPrice(fundValueAfter, totalSupplyAfter)).div(10 ** 18) >=
          IPoolManagerLogic(poolManagerLogic).minDepositUSD(),
        "need min deposit"
      );

      emit Deposit(
        address(this),
        _recipient,
        _asset,
        _amount,
        usdAmount,
        liquidityMinted,
        balance,
        fundValueAfter,
        totalSupplyAfter,
        block.timestamp
      );
    }

    _emitFactoryEvent();
  }

  /// @notice DEPRECATED: Use `withdrawSafe` instead.
  /// @dev Kept for backward compatibility. Not safe to use as it doesn't have high slippage protection.
  /// @param _fundTokenAmount Amount of pool tokens to withdraw
  function withdraw(uint256 _fundTokenAmount) external {
    _withdrawTo(
      msg.sender,
      _fundTokenAmount,
      new IPoolLogic.ComplexAsset[](IHasSupportedAsset(poolManagerLogic).getSupportedAssets().length)
    );
  }

  /// @notice DEPRECATED: Use `withdrawToSafe` instead.
  /// @dev Kept for backward compatibility. Not safe to use as it doesn't have high slippage protection.
  /// @param _recipient The address to withdraw to
  /// @param _fundTokenAmount Amount of pool tokens to withdraw
  function withdrawTo(address _recipient, uint256 _fundTokenAmount) external {
    _withdrawTo(
      _recipient,
      _fundTokenAmount,
      new IPoolLogic.ComplexAsset[](IHasSupportedAsset(poolManagerLogic).getSupportedAssets().length)
    );
  }

  /// @notice Use for withdrawing assets from the vault
  /// @param _fundTokenAmount Amount of fund tokens to withdraw
  /// @param _complexAssetsData Array with the same length as vault's supportedAssets. Each element contains:
  ///        - supportedAsset: Address of the supported asset
  ///        - withdrawData: Custom data needed for withdrawing complex assets like Aave positions
  ///        - slippageTolerance: Maximum acceptable slippage in basis points (e.g. 100 = 1%)
  function withdrawSafe(uint256 _fundTokenAmount, IPoolLogic.ComplexAsset[] memory _complexAssetsData) external {
    _withdrawTo(msg.sender, _fundTokenAmount, _complexAssetsData);
  }

  /// @notice Use for withdrawing assets from the vault to a specific address
  /// @param _recipient The address to withdraw to
  /// @param _fundTokenAmount Amount of fund tokens to withdraw
  /// @param _complexAssetsData Array with the same length as vault's supportedAssets. Each element contains:
  ///        - supportedAsset: Address of the supported asset
  ///        - withdrawData: Custom data needed for withdrawing complex assets like Aave positions
  ///        - slippageTolerance: Maximum acceptable slippage in basis points (e.g. 100 = 1%)
  function withdrawToSafe(
    address _recipient,
    uint256 _fundTokenAmount,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData
  ) external {
    _withdrawTo(_recipient, _fundTokenAmount, _complexAssetsData);
  }

  function _withdrawTo(
    address _recipient,
    uint256 _fundTokenAmount,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData
  ) internal nonReentrant whenNotFactoryPaused whenNotPaused {
    require(lastDeposit[msg.sender] < block.timestamp, "can withdraw soon");
    require(balanceOf(msg.sender) >= _fundTokenAmount, "not enough balance");

    WithdrawExecution memory execution;
    execution.supplyAfterBurn = totalSupply().sub(_fundTokenAmount);
    // Scoping to avoid stack too deep errors.
    {
      // Calculating how much pool token supply will be left after withdrawal and
      // whether or not this satisfies the min supply (100_000) check.
      // If the user is redeeming all the shares then this check passes.
      // Otherwise, they might have to reduce the amount to be withdrawn.
      require(execution.supplyAfterBurn >= 100_000 || execution.supplyAfterBurn == 0, "below threshold");
    }

    // calculate the manager fee
    (execution.fundValue, execution.feesMinted) = _mintManagerFee();

    {
      // Scoping to avoid stack too deep errors.
      (, , , uint256 exitFeeNumerator, uint256 denominator) = _managerFees();

      if (exitFeeNumerator > 0) {
        uint256 exitFee = _fundTokenAmount.mul(exitFeeNumerator).div(denominator);

        _fundTokenAmount = _fundTokenAmount.sub(exitFee);
        execution.supplyAfterBurn = execution.supplyAfterBurn.add(exitFee);

        address manager = _manager();
        require(transfer(manager, exitFee), "exitFee failed");

        emit ExitFeeMinted(manager, exitFee);
      }
    }

    // calculate the proportion
    uint256 portion = _fundTokenAmount.mul(10 ** 18).div(totalSupply());

    // first return funded tokens
    _burn(msg.sender, _fundTokenAmount);

    if (totalSupply() == 0) {
      tokenPriceAtLastFeeMint = 1e18;
    }

    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerLogic).getSupportedAssets();
    WithdrawnAsset[] memory withdrawnAssets = new WithdrawnAsset[](supportedAssets.length);
    uint256 index = 0;

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      (address asset, uint256 portionOfAssetBalance, bool externalWithdrawProcessed) = _withdrawProcessing(
        supportedAssets[i].asset,
        _recipient,
        portion,
        _complexAssetsData[i]
      );

      if (portionOfAssetBalance > 0) {
        require(asset != address(0), "need withdraw asset");
        // Ignoring return value for transfer as want to transfer no matter what happened
        asset.tryAssemblyCall(
          abi.encodeWithSelector(IERC20Upgradeable.transfer.selector, _recipient, portionOfAssetBalance)
        );
      }

      if (externalWithdrawProcessed || portionOfAssetBalance > 0) {
        withdrawnAssets[index] = WithdrawnAsset({
          asset: asset,
          amount: portionOfAssetBalance,
          externalWithdrawProcessed: externalWithdrawProcessed
        });
        index++;
      }
    }

    // Reduce length for withdrawnAssets to remove the empty items
    uint256 reduceLength = supportedAssets.length.sub(index);
    assembly {
      mstore(withdrawnAssets, sub(mload(withdrawnAssets), reduceLength))
    }

    uint256 valueWithdrawn = portion.mul(execution.fundValue).div(10 ** 18);

    // Invariant state check: actual difference between total vault value before and after withdrawal can not be more than value of portion withdrawn,
    // i.e. value of assets which actually left the vault can not be more than value of portion withdrawn.
    require(execution.fundValue.sub(_totalValue()) <= valueWithdrawn.add(1e15), "value mismatch");

    // Extra invariant for total supply after withdrawal. Could be an overkill, may consider removing if running into contract size issues.
    require(execution.supplyAfterBurn.add(execution.feesMinted) == totalSupply(), "supply mismatch");

    emit Withdrawal(
      address(this),
      _recipient,
      valueWithdrawn,
      _fundTokenAmount,
      balanceOf(_recipient),
      execution.fundValue.sub(valueWithdrawn),
      totalSupply(),
      withdrawnAssets,
      block.timestamp
    );
    _emitFactoryEvent();
  }

  /// @notice Perform any additional processing on withdrawal of asset
  /// @dev Checks for staked tokens and withdraws them to the investor account
  /// @param _asset Asset for withdrawal processing
  /// @param _to Investor account to send withdrawed tokens to
  /// @param _portion Portion of investor withdrawal of the total dHedge pool
  /// @param _complexAssetData Data for withdrawal processing
  /// @return withdrawAsset Asset to be withdrawed
  /// @return withdrawBalance Asset balance amount to be withdrawed
  /// @return externalWithdrawProcessed A boolean for success or fail transaction
  function _withdrawProcessing(
    address _asset,
    address _to,
    uint256 _portion,
    IPoolLogic.ComplexAsset memory _complexAssetData
  ) internal returns (address withdrawAsset, uint256 withdrawBalance, bool externalWithdrawProcessed) {
    WithdrawProcessing memory params;

    params.guard = IHasGuardInfo(factory).getAssetGuard(_asset);
    require(params.guard != address(0), "invalid guard");

    params.portionBalance = IAssetGuard(params.guard).getBalance(address(this), _asset).mul(_portion).div(10 ** 18);
    params.expectedWithdrawValue = _assetValue(_asset, params.portionBalance);

    IAssetGuard.MultiTransaction[] memory transactions;

    if (_complexAssetData.withdrawData.length > 0) {
      require(_asset == _complexAssetData.supportedAsset, "invalid asset data");

      (withdrawAsset, withdrawBalance, transactions) = IComplexAssetGuard(params.guard).withdrawProcessing(
        address(this),
        _asset,
        _portion,
        _to,
        _complexAssetData.withdrawData
      );
    } else {
      (withdrawAsset, withdrawBalance, transactions) = IAssetGuard(params.guard).withdrawProcessing(
        address(this),
        _asset,
        _portion,
        _to
      );
      params.regularProcessingUsed = true;
    }

    uint256 txCount = transactions.length;
    if (txCount > 0) {
      uint256 assetBalanceBefore;
      if (withdrawAsset != address(0)) {
        assetBalanceBefore = IERC20Upgradeable(withdrawAsset).balanceOf(address(this));
      }
      // In case of withdraw from aave position with debt, this loop is where flash loan starts and finishes its execution
      for (uint256 i = 0; i < txCount; i++) {
        externalWithdrawProcessed = transactions[i].to.tryAssemblyCall(transactions[i].txData);
      }
      // In case of withdraw from aave position with debt, remaining withdrawAsset gets added here
      if (withdrawAsset != address(0)) {
        // Get any balance increase after withdraw processing and add it to the withdraw balance
        uint256 assetBalanceAfter = IERC20Upgradeable(withdrawAsset).balanceOf(address(this));
        withdrawBalance = withdrawBalance.add(assetBalanceAfter.sub(assetBalanceBefore));
      }
    }

    // Leftover: kept for aave withdrawals with swap routed onchain, runs when slippage tolerance is provided
    if (params.regularProcessingUsed && _complexAssetData.slippageTolerance != 0 && withdrawAsset != address(0)) {
      // Ensure that actual value of tokens transferred is not less than the expected value, corrected by allowed tolerance
      require(
        _assetValue(withdrawAsset, withdrawBalance) >=
          params.expectedWithdrawValue.mul(10_000 - _complexAssetData.slippageTolerance).div(10_000),
        "high withdraw slippage"
      );
    }

    return (withdrawAsset, withdrawBalance, externalWithdrawProcessed);
  }

  /// @notice Private function to let pool talk to other protocol
  /// @dev execute transaction for the pool
  /// @param _to The destination address for pool to talk to
  /// @param _data The data that going to send in the transaction
  /// @return success A boolean for success or fail transaction
  function _execTransaction(
    address _to,
    bytes memory _data
  ) private nonReentrant whenNotFactoryPaused returns (bool success) {
    require(!IHasPausable(factory).tradingPausedPools(address(this)), "trading paused");

    require(_to != address(0), "invalid address");

    address contractGuard = IHasGuardInfo(factory).getContractGuard(_to);
    address assetGuard;
    address guard;
    uint16 txType;
    bool isPublic;

    if (contractGuard != address(0)) {
      guard = contractGuard;
      (txType, isPublic) = IGuard(contractGuard).txGuard(poolManagerLogic, _to, _data);
    }

    // invalid contract guard call, try asset guard
    if (txType == 0) {
      // no contract guard configured, get asset guard
      assetGuard = IHasGuardInfo(factory).getAssetGuard(_to);

      if (assetGuard == address(0)) {
        // If there is no contractGuard and no assetGuard then use the ERC20Guard for the transaction,
        // which will only allow a valid approve transaction
        address governanceAddress = IPoolFactory(factory).governanceAddress();
        assetGuard = IGovernance(governanceAddress).assetGuards(0); // get ERC20Guard (assetType 0)
      } else {
        // if asset is configured, ensure that it's enabled in the pool
        require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(_to), "asset disabled");
      }
      guard = assetGuard;
      (txType, isPublic) = IGuard(assetGuard).txGuard(poolManagerLogic, _to, _data);
    }

    require(txType > 0, "invalid transaction");

    require(isPublic || msg.sender == _manager() || msg.sender == _trader(), "only manager, trader, public");

    success = _to.tryAssemblyCall(_data);

    // call afterTxGuard to track transactions
    // to make it compatible with previous version, we use low-level call before calling afterTxGuard() function
    // the low level call will return `false` if its execution reverts
    // solhint-disable-next-line avoid-low-level-calls
    (bool hasFunction, bytes memory returnData) = guard.call(abi.encodeWithSignature("isTxTrackingGuard()"));
    if (hasFunction && abi.decode(returnData, (bool))) {
      ITxTrackingGuard(guard).afterTxGuard(poolManagerLogic, _to, _data);
    }

    emit TransactionExecuted(address(this), _manager(), txType, block.timestamp);
    _emitFactoryEvent();
  }

  /// @notice Exposed function to let pool talk to other protocol
  /// @dev Execute single transaction for the pool
  /// @param to The destination address for pool to talk to
  /// @param data The data that going to send in the transaction
  /// @return success A boolean for success or fail transaction
  function execTransaction(address to, bytes calldata data) external returns (bool success) {
    return _execTransaction(to, data);
  }

  /// @notice Exposed function to let pool talk to other protocol
  /// @dev Execute multiple transactions for the pool
  /// @param txs Array of structs, each consisting of address and data
  function execTransactions(TxToExecute[] calldata txs) external {
    for (uint256 i; i < txs.length; i++) {
      require(_execTransaction(txs[i].to, txs[i].data), "tx failed");
    }
  }

  /// @notice Get fund summary of the pool
  /// @return Fund summary of the pool
  function getFundSummary() external view returns (FundSummary memory) {
    (
      uint256 performanceFeeNumerator,
      uint256 managementFeeNumerator,
      uint256 entryFeeNumerator,
      uint256 exitFeeNumerator,
      uint256 denominator
    ) = _managerFees();

    return
      FundSummary(
        name(),
        totalSupply(),
        _totalValue(),
        _manager(),
        IManaged(poolManagerLogic).managerName(),
        creationTime,
        privatePool,
        performanceFeeNumerator,
        managementFeeNumerator,
        denominator,
        exitFeeNumerator,
        denominator,
        entryFeeNumerator
      );
  }

  /// @notice Get price of the pool token adjusted for any unminted manager fees
  /// @return price A price of the pool
  function tokenPrice() external view returns (uint256 price) {
    uint256 fundValue = _totalValue();
    uint256 tokenSupply = totalSupply().add(calculateAvailableManagerFee(fundValue));

    price = _tokenPrice(fundValue, tokenSupply);
  }

  /// @notice Get price of the pool token without manager fees (inaccurately bigger because supply is less than potentially could be)
  /// @return price A price of the pool
  function tokenPriceWithoutManagerFee() external view returns (uint256 price) {
    price = _tokenPrice(_totalValue(), totalSupply());
  }

  /// @notice Get price of the asset internal call
  /// @param _fundValue The total fund value of the pool
  /// @param _tokenSupply The total token supply of the pool
  /// @return price A price of the asset
  function _tokenPrice(uint256 _fundValue, uint256 _tokenSupply) internal pure returns (uint256 price) {
    if (_tokenSupply == 0 || _fundValue == 0) return 0;
    price = _fundValue.mul(10 ** 18).div(_tokenSupply);
  }

  /// @notice Get available manager fee of the pool
  /// @dev Can be used on the frontend by passing in fund value
  /// @param _fundValue The total fund value of the pool
  /// @return fee available manager fee of the pool
  function calculateAvailableManagerFee(uint256 _fundValue) public view returns (uint256 fee) {
    (uint256 performanceFeeNumerator, uint256 managementFeeNumerator, , , uint256 denominator) = _managerFees();

    (uint256 performanceFee, uint256 streamingFee) = _availableManagerFee(
      _fundValue,
      totalSupply(),
      performanceFeeNumerator,
      managementFeeNumerator,
      denominator
    );

    return performanceFee.add(streamingFee);
  }

  /// @notice Get available manager fee of the pool internal call
  /// @param _fundValue The total fund value of the pool
  /// @param _tokenSupply The total token supply of the pool
  /// @param _performanceFeeNumerator Performance fee numerator
  /// @param _managerFeeNumerator Management fee numerator
  /// @param _feeDenominator Fee denominator
  /// @return performanceFee Performance fee generated by the pool
  /// @return streamingFee Management fee generated by the pool
  function _availableManagerFee(
    uint256 _fundValue,
    uint256 _tokenSupply,
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    uint256 _feeDenominator
  ) internal view returns (uint256 performanceFee, uint256 streamingFee) {
    if (_tokenSupply == 0 || _fundValue == 0) return (0, 0);

    uint256 currentTokenPrice = _fundValue.mul(10 ** 18).div(_tokenSupply);

    if (currentTokenPrice > tokenPriceAtLastFeeMint) {
      uint256 feeUsdAmount = (
        (currentTokenPrice.sub(tokenPriceAtLastFeeMint)).mul(_performanceFeeNumerator).mul(_tokenSupply)
      ).div(_feeDenominator.mul(1e18));
      performanceFee = feeUsdAmount.mul(_tokenSupply).div(_fundValue.sub(feeUsdAmount));
    }

    // this timestamp for old pools would be zero at the first time
    if (lastFeeMintTime != 0) {
      uint256 timeChange = block.timestamp.sub(lastFeeMintTime);
      streamingFee = _tokenSupply.mul(timeChange).mul(_managerFeeNumerator).div(_feeDenominator).div(365 days);
    }
  }

  /// @notice Mint the manager fee of the pool
  function mintManagerFee() external nonReentrant whenNotFactoryPaused whenNotPaused {
    _mintManagerFee();
  }

  /// @notice Get mint manager fee of the pool internal call
  /// @return fundValue The total fund value of the pool
  /// @return amountMinted The amount of manager fee minted
  function _mintManagerFee() internal returns (uint256 fundValue, uint256 amountMinted) {
    fundValue = _totalValue();
    uint256 tokenSupply = totalSupply();

    (uint256 performanceFeeNumerator, uint256 managementFeeNumerator, , , uint256 denominator) = _managerFees();

    (uint256 performanceFee, uint256 streamingFee) = _availableManagerFee(
      fundValue,
      tokenSupply,
      performanceFeeNumerator,
      managementFeeNumerator,
      denominator
    );
    amountMinted = performanceFee.add(streamingFee);

    (uint256 daoFeeNumerator, uint256 daoFeeDenominator) = IHasDaoInfo(factory).getDaoFee();

    uint256 daoFee = amountMinted.mul(daoFeeNumerator).div(daoFeeDenominator);
    uint256 managerFee = amountMinted.sub(daoFee);
    uint256 currentTokenPrice = _tokenPrice(fundValue, tokenSupply);

    if (tokenPriceAtLastFeeMint < currentTokenPrice) {
      tokenPriceAtLastFeeMint = currentTokenPrice;
    }

    // If the `streamingFee` is 0 then updating `lastFeeMintTime` can result in reduced streaming fee revenue.
    // This is due to rounding down when calculating `streamingFee` in `_availableManagerFee`.
    if (streamingFee > 0) lastFeeMintTime = block.timestamp;

    if (daoFee > 0) _mint(IHasDaoInfo(factory).daoAddress(), daoFee);

    if (managerFee > 0) _mint(_manager(), managerFee);

    emit ManagerFeeMinted(address(this), _manager(), amountMinted, daoFee, managerFee, tokenPriceAtLastFeeMint);
    _emitFactoryEvent();
  }

  /// @notice Calculate lockup cooldown applied to the investor after pool deposit
  /// @param _currentBalance Investor's current pool tokens balance
  /// @param _liquidityMinted Liquidity to be minted to investor after pool deposit
  /// @param _newCooldown New cooldown lockup time
  /// @param _lastCooldown Last cooldown lockup time applied to investor
  /// @param _lastDepositTime Timestamp when last pool deposit happened
  /// @param _blockTimestamp Timestamp of a block
  /// @return cooldown New lockup cooldown to be applied to investor address
  function _calculateCooldown(
    uint256 _currentBalance,
    uint256 _liquidityMinted,
    uint256 _newCooldown,
    uint256 _lastCooldown,
    uint256 _lastDepositTime,
    uint256 _blockTimestamp
  ) internal pure returns (uint256 cooldown) {
    // Get timestamp when current cooldown ends
    uint256 cooldownEndsAt = _lastDepositTime.add(_lastCooldown);
    // Current exit remaining cooldown
    uint256 remainingCooldown = cooldownEndsAt < _blockTimestamp ? 0 : cooldownEndsAt.sub(_blockTimestamp);
    // If it's first deposit with zero liquidity, no cooldown should be applied
    if (_currentBalance == 0 && _liquidityMinted == 0) {
      cooldown = 0;
      // If it's first deposit, new cooldown should be applied
    } else if (_currentBalance == 0) {
      cooldown = _newCooldown;
      // If zero liquidity or new cooldown reduces remaining cooldown, apply remaining
    } else if (_liquidityMinted == 0 || _newCooldown < remainingCooldown) {
      cooldown = remainingCooldown;
      // For the rest cases calculate cooldown based on current balance and liquidity minted
    } else {
      // If the user already owns liquidity, the additional lockup should be in proportion to their existing liquidity.
      // Calculated as _newCooldown * _liquidityMinted / _currentBalance
      // Aggregate additional and remaining cooldowns
      uint256 aggregatedCooldown = _newCooldown.mul(_liquidityMinted).div(_currentBalance).add(remainingCooldown);
      // Resulting value is capped at new cooldown time (shouldn't be bigger) and falls back to one second in case of zero
      cooldown = aggregatedCooldown > _newCooldown
        ? _newCooldown
        : aggregatedCooldown != 0
          ? aggregatedCooldown
          : 1;
    }
  }

  /// @notice Get how much time remained for the depositor before they can withdraw from the pool
  /// @param _depositor The address of the depositor
  /// @return remaining The remaining lockup time for the depositor
  function getExitRemainingCooldown(address _depositor) public view returns (uint256 remaining) {
    uint256 cooldownFinished = lastDeposit[_depositor].add(lastExitCooldown[_depositor]);

    if (cooldownFinished < block.timestamp) return 0;

    remaining = cooldownFinished.sub(block.timestamp);
  }

  /// @notice Set address for pool manager logic
  /// @param _poolManagerLogic Address of the pool manager logic
  function setPoolManagerLogic(address _poolManagerLogic) external {
    require(_poolManagerLogic != address(0), "invalid address");
    require(msg.sender == factory || msg.sender == IHasOwnable(factory).owner(), "only owner, factory");

    poolManagerLogic = _poolManagerLogic;
    emit PoolManagerLogicSet(_poolManagerLogic, msg.sender);
  }

  function _manager() internal view returns (address manager) {
    manager = IManaged(poolManagerLogic).manager();
  }

  function _trader() internal view returns (address trader) {
    trader = IManaged(poolManagerLogic).trader();
  }

  function _exitCooldown() internal view returns (uint256 cooldown) {
    cooldown = IHasFeeInfo(factory).getExitCooldown();
  }

  function _totalValue() internal view returns (uint256 totalValue) {
    totalValue = IPoolManagerLogic(poolManagerLogic).totalFundValue();
  }

  function _assetValue(address _asset, uint256 _amount) internal view returns (uint256 assetValue) {
    assetValue = IPoolManagerLogic(poolManagerLogic).assetValue(_asset, _amount);
  }

  function _managerFees()
    internal
    view
    returns (uint256 performance, uint256 management, uint256 entry, uint256 exit, uint256 denominator)
  {
    (performance, management, entry, exit, denominator) = IPoolManagerLogic(poolManagerLogic).getFee();
  }

  function _isMemberAllowed(address _member) internal view returns (bool allowed) {
    allowed = IPoolManagerLogic(poolManagerLogic).isMemberAllowed(_member);
  }

  /// @notice Executes operations after receiving a flashloan from Aave
  /// @param assets Array of asset addresses that were flash loaned
  /// @param amounts Array of amounts that were flash loaned
  /// @param premiums Array of premiums to pay for each borrowed asset
  /// @param initiator Address that initiated the flash loan
  /// @param params Arbitrary bytes passed to the receiver
  /// @return success Boolean indicating whether the operation was successful
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external override returns (bool success) {
    require(initiator == address(this), "only pool flash loan origin");

    address aaveLendingPoolAssetGuard = IHasGuardInfo(factory).getAssetGuard(msg.sender);
    require(
      aaveLendingPoolAssetGuard != address(0) &&
        msg.sender == IAaveLendingPoolAssetGuard(aaveLendingPoolAssetGuard).aaveLendingPool(),
      "invalid lending pool"
    );

    uint256 withdrawAssetBalanceBefore = IERC20Upgradeable(assets[0]).balanceOf(address(this));

    IAssetGuard.MultiTransaction[] memory transactions = IAaveLendingPoolAssetGuard(aaveLendingPoolAssetGuard)
      .flashloanProcessing(address(this), assets[0], amounts[0], premiums[0], params);

    for (uint256 i; i < transactions.length; ++i) {
      success = transactions[i].to.tryAssemblyCall(transactions[i].txData);
    }

    // Liquidation of collateral not enough to pay off debt, flashloan repayment stealing pool's asset
    require(
      withdrawAssetBalanceBefore.add(premiums[0]) <= IERC20Upgradeable(assets[0]).balanceOf(address(this)),
      "high slippage"
    );
  }

  /// @notice Emits an event through the factory, so we can just listen to the factory offchain
  function _emitFactoryEvent() internal {
    IPoolFactory(factory).emitPoolEvent();
  }

  /// @notice Support safeTransfers from ERC721 asset contracts
  /// @param operator The address which called `safeTransferFrom` function
  /// @param from The address which previously owned the token
  /// @param tokenId The NFT identifier which is being transferred
  /// @param data Additional data with no specified format
  /// @return magicSelector Returns the function selector to confirm ERC721 receiver implementation
  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) external override returns (bytes4 magicSelector) {
    address contractGuard = IHasGuardInfo(factory).getContractGuard(operator);

    // Only guarded contract can initiate ERC721 transfers
    require(contractGuard != address(0), "only guarded address");

    require(IERC721VerifyingGuard(contractGuard).verifyERC721(operator, from, tokenId, data), "not verified");

    magicSelector = IERC721ReceiverUpgradeable.onERC721Received.selector;
  }

  uint256[47] private __gap;
}
