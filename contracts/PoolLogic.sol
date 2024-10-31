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
// Copyright (c) 2021 dHEDGE DAO
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

  struct WithdrawProcessing {
    uint256 portionBalance;
    uint256 expectedWithdrawValue;
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
  /// @param from address of the token owner
  /// @param to address of the token receiver
  /// @param amount amount of tokens to transfer
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    super._beforeTokenTransfer(from, to, amount);
    // Minting
    if (from == address(0)) {
      return;
    }

    // If the pool is private, either the recipient has to be a pool member or the transaction should be burning the fund tokens.
    // The latter is required in case a user deposited into the pool when the pool was public and then the pool was made private
    // in which case the user should be able to withdraw their funds.
    require(!privatePool || _isMemberAllowed(to) || to == address(0), "only members");

    if (IPoolFactory(factory).receiverWhitelist(to) == true) {
      return;
    }

    require(getExitRemainingCooldown(from) == 0, "cooldown active");
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

  function depositFor(address _recipient, address _asset, uint256 _amount) external returns (uint256 liquidityMinted) {
    return _depositFor(_recipient, _asset, _amount, _exitCooldown());
  }

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
    require(_recipient == _manager() || !privatePool || _isMemberAllowed(_recipient), "only members");

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

    uint256 fundValue = _mintManagerFee();

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

        _mint(_manager(), entryFee);
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

  /// @notice Not recommended to use. Use `withdrawSafe` instead
  /// @dev Kept for backward compatibility
  function withdraw(uint256 _fundTokenAmount) external {
    _withdrawTo(msg.sender, _fundTokenAmount, 10_000);
  }

  /// @notice Not recommended to use. Use `withdrawSafe` instead
  /// @dev Kept for backward compatibility
  function withdrawTo(address _recipient, uint256 _fundTokenAmount) external {
    _withdrawTo(_recipient, _fundTokenAmount, 10_000);
  }

  /// @notice Most recent function to be used for withdrawing assets from the vault
  /// @dev This is for vaults that can have slippage on withdrawal, eg. portfolio has Aave positions with debt
  function withdrawSafe(uint256 _fundTokenAmount, uint256 _slippageTolerance) external {
    _withdrawTo(msg.sender, _fundTokenAmount, _slippageTolerance);
  }

  /// @notice Most recent function to be used for withdrawing assets from the vault to a specific address
  /// @dev This is for vaults that can have slippage on withdrawal, eg. portfolio has Aave positions with debt
  function withdrawToSafe(address _recipient, uint256 _fundTokenAmount, uint256 _slippageTolerance) external {
    _withdrawTo(_recipient, _fundTokenAmount, _slippageTolerance);
  }

  /// @notice Withdraw assets based on the fund token amount
  /// @param _recipient The address to withdraw to
  /// @param _fundTokenAmount Amount of fund tokens to withdraw
  /// @param _slippageTolerance Slippage tolerance, 10_000 = 100%, 100 = 1%, 10 = 0.1%, 1 = 0.01%
  function _withdrawTo(
    address _recipient,
    uint256 _fundTokenAmount,
    uint256 _slippageTolerance
  ) internal nonReentrant whenNotFactoryPaused whenNotPaused {
    require(lastDeposit[msg.sender] < block.timestamp, "can withdraw soon");
    require(balanceOf(msg.sender) >= _fundTokenAmount, "not enough balance");
    require(_slippageTolerance <= 10_000, "invalid tolerance");

    // Scoping to avoid "stack-too-deep" errors.
    {
      // Calculating how much pool token supply will be left after withdrawal and
      // whether or not this satisfies the min supply (100_000) check.
      // If the user is redeeming all the shares then this check passes.
      // Otherwise, they might have to reduce the amount to be withdrawn.
      uint256 supplyAfter = totalSupply().sub(_fundTokenAmount);
      require(supplyAfter >= 100_000 || supplyAfter == 0, "below supply threshold");
    }

    // calculate the manager fee
    uint256 fundValue = _mintManagerFee();

    {
      // Scope to avoid stack too deep error
      (, , , uint256 exitFeeNumerator, uint256 denominator) = _managerFees();

      if (exitFeeNumerator > 0) {
        uint256 exitFee = _fundTokenAmount.mul(exitFeeNumerator).div(denominator);

        _fundTokenAmount = _fundTokenAmount.sub(exitFee);

        require(transfer(_manager(), exitFee), "exit fee transfer failed");
      }
    }

    // calculate the proportion
    uint256 portion = _fundTokenAmount.mul(10 ** 18).div(totalSupply());

    // first return funded tokens
    _burn(msg.sender, _fundTokenAmount);

    if (totalSupply() == 0) {
      tokenPriceAtLastFeeMint = 1e18;
    }

    // TODO: Combining into one line to fix stack too deep,
    //       need to refactor some variables into struct in order to have more variables
    IHasSupportedAsset.Asset[] memory _supportedAssets = IHasSupportedAsset(poolManagerLogic).getSupportedAssets();
    WithdrawnAsset[] memory withdrawnAssets = new WithdrawnAsset[](_supportedAssets.length);
    uint256 index = 0;

    for (uint256 i = 0; i < _supportedAssets.length; i++) {
      (address asset, uint256 portionOfAssetBalance, bool externalWithdrawProcessed) = _withdrawProcessing(
        _supportedAssets[i].asset,
        _recipient,
        portion,
        _slippageTolerance
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
    uint256 reduceLength = _supportedAssets.length.sub(index);
    assembly {
      mstore(withdrawnAssets, sub(mload(withdrawnAssets), reduceLength))
    }

    uint256 valueWithdrawn = portion.mul(fundValue).div(10 ** 18);

    emit Withdrawal(
      address(this),
      msg.sender,
      valueWithdrawn,
      _fundTokenAmount,
      balanceOf(msg.sender),
      fundValue.sub(valueWithdrawn),
      totalSupply(),
      withdrawnAssets,
      block.timestamp
    );
    _emitFactoryEvent();
  }

  /// @notice Perform any additional processing on withdrawal of asset
  /// @dev Checks for staked tokens and withdraws them to the investor account
  /// @param asset Asset for withdrawal processing
  /// @param to Investor account to send withdrawed tokens to
  /// @param portion Portion of investor withdrawal of the total dHedge pool
  /// @param slippageTolerance Slippage tolerance for withdrawal
  /// @return withdrawAsset Asset to be withdrawed
  /// @return withdrawBalance Asset balance amount to be withdrawed
  /// @return externalWithdrawProcessed A boolean for success or fail transaction
  function _withdrawProcessing(
    address asset,
    address to,
    uint256 portion,
    uint256 slippageTolerance
  )
    internal
    returns (
      address, // withdrawAsset
      uint256, // withdrawBalance
      bool externalWithdrawProcessed
    )
  {
    // Withdraw any external tokens (eg. staked tokens in other contracts)
    address guard = IHasGuardInfo(factory).getAssetGuard(asset);
    require(guard != address(0), "invalid guard");

    WithdrawProcessing memory params;
    params.portionBalance = IAssetGuard(guard).getBalance(address(this), asset).mul(portion).div(10 ** 18);
    // Value of the portion of the asset to be withdrawn
    params.expectedWithdrawValue = _assetValue(asset, params.portionBalance);

    (address withdrawAsset, uint256 withdrawBalance, IAssetGuard.MultiTransaction[] memory transactions) = IAssetGuard(
      guard
    ).withdrawProcessing(address(this), asset, portion, to);

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
        // get any balance increase after withdraw processing and add it to the withdraw balance
        uint256 assetBalanceAfter = IERC20Upgradeable(withdrawAsset).balanceOf(address(this));
        withdrawBalance = withdrawBalance.add(assetBalanceAfter.sub(assetBalanceBefore));
      }
    }
    // solhint-disable-next-line avoid-low-level-calls
    (bool hasFunction, bytes memory answer) = guard.call(abi.encodeWithSignature("isSlippageCheckingGuard()"));
    // check slippage after asset's withdraw processing if required in its guard (eg. Aave)
    if (hasFunction && abi.decode(answer, (bool)) && withdrawAsset != address(0)) {
      // Ensure that actual value of tokens transferred is not less than the expected value, corrected by allowed tolerance
      require(
        _assetValue(withdrawAsset, withdrawBalance) >=
          params.expectedWithdrawValue.mul(10_000 - slippageTolerance).div(10_000),
        "high withdraw slippage"
      );
    }

    return (withdrawAsset, withdrawBalance, externalWithdrawProcessed);
  }

  /// @notice Private function to let pool talk to other protocol
  /// @dev execute transaction for the pool
  /// @param to The destination address for pool to talk to
  /// @param data The data that going to send in the transaction
  /// @return success A boolean for success or fail transaction
  function _execTransaction(
    address to,
    bytes memory data
  ) private nonReentrant whenNotFactoryPaused returns (bool success) {
    require(to != address(0), "invalid address");

    address contractGuard = IHasGuardInfo(factory).getContractGuard(to);
    address assetGuard;
    address guard;
    uint16 txType;
    bool isPublic;

    if (contractGuard != address(0)) {
      guard = contractGuard;
      (txType, isPublic) = IGuard(contractGuard).txGuard(poolManagerLogic, to, data);
    }

    // invalid contract guard call, try asset guard
    if (txType == 0) {
      // no contract guard configured, get asset guard
      assetGuard = IHasGuardInfo(factory).getAssetGuard(to);

      if (assetGuard == address(0)) {
        // If there is no contractGuard and no assetGuard then use the ERC20Guard for the transaction,
        // which will only allow a valid approve transaction
        address governanceAddress = IPoolFactory(factory).governanceAddress();
        assetGuard = IGovernance(governanceAddress).assetGuards(0); // get ERC20Guard (assetType 0)
      } else {
        // if asset is configured, ensure that it's enabled in the pool
        require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(to), "asset disabled");
      }
      guard = assetGuard;
      (txType, isPublic) = IGuard(assetGuard).txGuard(poolManagerLogic, to, data);
    }

    require(txType > 0, "invalid transaction");

    require(isPublic || msg.sender == _manager() || msg.sender == _trader(), "only manager, trader, public");

    success = to.tryAssemblyCall(data);

    // call afterTxGuard to track transactions
    // to make it compatible with previous version, we use low-level call before calling afterTxGuard() function
    // the low level call will return `false` if its execution reverts
    // solhint-disable-next-line avoid-low-level-calls
    (bool hasFunction, bytes memory returnData) = guard.call(abi.encodeWithSignature("isTxTrackingGuard()"));
    if (hasFunction && abi.decode(returnData, (bool))) {
      ITxTrackingGuard(guard).afterTxGuard(poolManagerLogic, to, data);
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
    for (uint256 i = 0; i < txs.length; i++) {
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

  /// @notice Get price of the asset adjusted for any unminted manager fees
  /// @param price A price of the asset
  function tokenPrice() external view returns (uint256 price) {
    uint256 fundValue = _totalValue();
    uint256 tokenSupply = totalSupply().add(calculateAvailableManagerFee(fundValue));

    price = _tokenPrice(fundValue, tokenSupply);
  }

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
  /// @param fundValue The total fund value of the pool
  /// @return fee available manager fee of the pool
  function calculateAvailableManagerFee(uint256 fundValue) public view returns (uint256 fee) {
    (uint256 performanceFeeNumerator, uint256 managementFeeNumerator, , , uint256 denominator) = _managerFees();

    (uint256 performanceFee, uint256 streamingFee) = _availableManagerFee(
      fundValue,
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
  /// @param _performanceFeeNumerator The manager fee numerator
  /// @param _managerFeeNumerator The streaming fee numerator
  /// @param _feeDenominator The fee denominator
  /// @return performanceFee The performance fee generated by the pool
  /// @return streamingFee The streaming fee generated by the pool
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
  function mintManagerFee() external whenNotFactoryPaused whenNotPaused {
    _mintManagerFee();
  }

  /// @notice Get mint manager fee of the pool internal call
  /// @return fundValue The total fund value of the pool
  function _mintManagerFee() internal returns (uint256 fundValue) {
    fundValue = IPoolManagerLogic(poolManagerLogic).totalFundValueMutable();
    uint256 tokenSupply = totalSupply();

    (uint256 performanceFeeNumerator, uint256 managementFeeNumerator, , , uint256 denominator) = _managerFees();

    (uint256 performanceFee, uint256 streamingFee) = _availableManagerFee(
      fundValue,
      tokenSupply,
      performanceFeeNumerator,
      managementFeeNumerator,
      denominator
    );
    uint256 available = performanceFee.add(streamingFee);

    (uint256 daoFeeNumerator, uint256 daoFeeDenominator) = IHasDaoInfo(factory).getDaoFee();

    uint256 daoFee = available.mul(daoFeeNumerator).div(daoFeeDenominator);
    uint256 managerFee = available.sub(daoFee);
    uint256 currentTokenPrice = _tokenPrice(fundValue, tokenSupply);

    if (tokenPriceAtLastFeeMint < currentTokenPrice) {
      tokenPriceAtLastFeeMint = currentTokenPrice;
    }

    // If the `streamingFee` is 0 then updating `lastFeeMintTime` can result in reduced streaming fee revenue.
    // This is due to rounding down when calculating `streamingFee` in `_availableManagerFee`.
    if (streamingFee > 0) lastFeeMintTime = block.timestamp;

    if (daoFee > 0) _mint(IHasDaoInfo(factory).daoAddress(), daoFee);

    if (managerFee > 0) _mint(_manager(), managerFee);

    emit ManagerFeeMinted(address(this), _manager(), available, daoFee, managerFee, tokenPriceAtLastFeeMint);
    _emitFactoryEvent();
  }

  /// @notice Calculate lockup cooldown applied to the investor after pool deposit
  /// @param currentBalance Investor's current pool tokens balance
  /// @param liquidityMinted Liquidity to be minted to investor after pool deposit
  /// @param newCooldown New cooldown lockup time
  /// @param lastCooldown Last cooldown lockup time applied to investor
  /// @param lastDepositTime Timestamp when last pool deposit happened
  /// @param blockTimestamp Timestamp of a block
  /// @return cooldown New lockup cooldown to be applied to investor address
  function _calculateCooldown(
    uint256 currentBalance,
    uint256 liquidityMinted,
    uint256 newCooldown,
    uint256 lastCooldown,
    uint256 lastDepositTime,
    uint256 blockTimestamp
  ) internal pure returns (uint256 cooldown) {
    // Get timestamp when current cooldown ends
    uint256 cooldownEndsAt = lastDepositTime.add(lastCooldown);
    // Current exit remaining cooldown
    uint256 remainingCooldown = cooldownEndsAt < blockTimestamp ? 0 : cooldownEndsAt.sub(blockTimestamp);
    // If it's first deposit with zero liquidity, no cooldown should be applied
    if (currentBalance == 0 && liquidityMinted == 0) {
      cooldown = 0;
      // If it's first deposit, new cooldown should be applied
    } else if (currentBalance == 0) {
      cooldown = newCooldown;
      // If zero liquidity or new cooldown reduces remaining cooldown, apply remaining
    } else if (liquidityMinted == 0 || newCooldown < remainingCooldown) {
      cooldown = remainingCooldown;
      // For the rest cases calculate cooldown based on current balance and liquidity minted
    } else {
      // If the user already owns liquidity, the additional lockup should be in proportion to their existing liquidity.
      // Calculated as newCooldown * liquidityMinted / currentBalance
      // Aggregate additional and remaining cooldowns
      uint256 aggregatedCooldown = newCooldown.mul(liquidityMinted).div(currentBalance).add(remainingCooldown);
      // Resulting value is capped at new cooldown time (shouldn't be bigger) and falls back to one second in case of zero
      cooldown = aggregatedCooldown > newCooldown
        ? newCooldown
        : aggregatedCooldown != 0
          ? aggregatedCooldown
          : 1;
    }
  }

  /// @notice Get exit remaining time of the pool
  /// @return remaining The remaining exit time of the pool
  function getExitRemainingCooldown(address sender) public view returns (uint256 remaining) {
    uint256 cooldownFinished = lastDeposit[sender].add(lastExitCooldown[sender]);

    if (cooldownFinished < block.timestamp) return 0;

    remaining = cooldownFinished.sub(block.timestamp);
  }

  /// @notice Set address for pool manager logic
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

  /// @inheritdoc IFlashLoanReceiver
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
    require(withdrawAssetBalanceBefore <= IERC20Upgradeable(assets[0]).balanceOf(address(this)), "high slippage");
  }

  /// @notice Emits an event through the factory, so we can just listen to the factory offchain
  function _emitFactoryEvent() internal {
    IPoolFactory(factory).emitPoolEvent();
  }

  /// @notice Support safeTransfers from ERC721 asset contracts
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
