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
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
//
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./interfaces/IERC20Extended.sol";
import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IHasFeeInfo.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IHasPausable.sol";
import "./interfaces/IPoolManagerLogic.sol";
import "./interfaces/IHasSupportedAsset.sol";
import "./interfaces/IHasOwnable.sol";
import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IManaged.sol";
import "./interfaces/guards/IGuard.sol";
import "./interfaces/guards/ITxTrackingGuard.sol";
import "./interfaces/guards/IAssetGuard.sol";
import "./interfaces/guards/IAaveLendingPoolAssetGuard.sol";
import "./interfaces/guards/IERC721VerifyingGuard.sol";
import "./interfaces/IGovernance.sol";
import "./utils/AddressHelper.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @notice Logic implementation for pool
contract PoolLogic is ERC20Upgradeable, ReentrancyGuardUpgradeable, IERC721ReceiverUpgradeable {
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

  struct WithdrawnAsset {
    address asset;
    uint256 amount;
    bool externalWithdrawProcessed;
  }

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

  // Manager fees
  uint256 public tokenPriceAtLastFeeMint;

  mapping(address => uint256) public lastDeposit;

  address public poolManagerLogic;

  mapping(address => uint256) public lastWhitelistTransfer;

  uint256 public lastFeeMintTime;

  mapping(address => uint256) public lastExitCooldown;

  modifier onlyAllowed(address _recipient) {
    require(_recipient == manager() || !privatePool || isMemberAllowed(_recipient), "only members allowed");
    _;
  }

  modifier onlyManager() {
    require(msg.sender == manager(), "only manager");
    _;
  }

  modifier whenNotFactoryPaused() {
    require(!IHasPausable(factory).isPaused(), "contracts paused");
    _;
  }

  modifier whitelistedForCustomCooldown() {
    require(IPoolFactory(factory).customCooldownWhitelist(msg.sender), "only whitelisted sender");
    _;
  }

  modifier whenNotPaused() {
    require(!IHasPausable(factory).pausedPools(address(this)), "pool is paused");
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
    require(_factory != address(0), "Invalid factory");
    __ERC20_init(_fundName, _fundSymbol);
    __ReentrancyGuard_init();

    factory = _factory;
    _setPoolPrivacy(_privatePool);
    creator = msg.sender;
    creationTime = block.timestamp;
    lastFeeMintTime = block.timestamp;

    tokenPriceAtLastFeeMint = 10**18;
  }

  /// @notice Before token transfer hook
  /// @param from address of the token owner
  /// @param to address of the token receiver
  /// @param amount amount of tokens to transfer
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override {
    super._beforeTokenTransfer(from, to, amount);
    // Minting
    if (from == address(0)) {
      return;
    }

    if (IPoolFactory(factory).receiverWhitelist(to) == true) {
      return;
    }

    require(getExitRemainingCooldown(from) == 0, "cooldown active");
  }

  /// @notice Set the pool privacy
  /// @param _privatePool true if the pool is private, false otherwise
  function setPoolPrivate(bool _privatePool) external onlyManager {
    require(privatePool != _privatePool, "flag must be different");

    _setPoolPrivacy(_privatePool);
    emitFactoryEvent();
  }

  /// @notice Set the pool privacy internal call
  /// @param _privacy true if the pool is private, false otherwise
  function _setPoolPrivacy(bool _privacy) internal {
    privatePool = _privacy;

    emit PoolPrivacyUpdated(_privacy);
  }

  /// @notice Deposit funds into the pool
  /// @param _asset Address of the token
  /// @param _amount Amount of tokens to deposit
  /// @return liquidityMinted Amount of liquidity minted
  function deposit(address _asset, uint256 _amount) external returns (uint256 liquidityMinted) {
    return _depositFor(msg.sender, _asset, _amount, IHasFeeInfo(factory).getExitCooldown());
  }

  function depositFor(
    address _recipient,
    address _asset,
    uint256 _amount
  ) external returns (uint256 liquidityMinted) {
    return _depositFor(_recipient, _asset, _amount, IHasFeeInfo(factory).getExitCooldown());
  }

  function depositForWithCustomCooldown(
    address _recipient,
    address _asset,
    uint256 _amount,
    uint256 _cooldown
  ) external whitelistedForCustomCooldown returns (uint256 liquidityMinted) {
    require(_cooldown >= 5 minutes, "cooldown must exceed 5 mins");
    require(_cooldown <= IHasFeeInfo(factory).getExitCooldown(), "cant exceed default cooldown");

    return _depositFor(_recipient, _asset, _amount, _cooldown);
  }

  function _depositFor(
    address _recipient,
    address _asset,
    uint256 _amount,
    uint256 _cooldown
  ) private onlyAllowed(_recipient) whenNotFactoryPaused whenNotPaused returns (uint256 liquidityMinted) {
    require(IPoolManagerLogic(poolManagerLogic).isDepositAsset(_asset), "invalid deposit asset");

    uint256 fundValue = _mintManagerFee();

    uint256 totalSupplyBefore = totalSupply();

    _asset.tryAssemblyCall(
      abi.encodeWithSelector(IERC20Upgradeable.transferFrom.selector, msg.sender, address(this), _amount)
    );

    uint256 usdAmount = IPoolManagerLogic(poolManagerLogic).assetValue(_asset, _amount);

    // Scoping to avoid stack too deep errors.
    {
      (, , uint256 entryFeeNumerator, uint256 denominator) = IPoolManagerLogic(poolManagerLogic).getFee();

      if (totalSupplyBefore > 0) {
        // Accounting for entry fee while calculating liquidity to be minted.
        liquidityMinted = usdAmount.mul(totalSupplyBefore).mul(denominator.sub(entryFeeNumerator)).div(fundValue).div(
          denominator
        );
      } else {
        // This is equivalent to doing liquidityMinted = liquidityMinted * (1 - entryFeeNumerator/denominator).
        liquidityMinted = usdAmount.mul(denominator.sub(entryFeeNumerator)).div(denominator);
      }
    }

    // Note: We are making it impossible for someone to mint liquidity < 100_000.
    // This is so that we can mitigate the inflation attack.
    require(liquidityMinted >= 100_000, "invalid liquidityMinted");

    lastExitCooldown[_recipient] = calculateCooldown(
      balanceOf(_recipient),
      liquidityMinted,
      _cooldown,
      lastExitCooldown[_recipient],
      lastDeposit[_recipient],
      block.timestamp
    );
    lastDeposit[_recipient] = block.timestamp;

    _mint(_recipient, liquidityMinted);

    uint256 balance = balanceOf(_recipient);
    uint256 fundValueAfter = fundValue.add(usdAmount);
    uint256 totalSupplyAfter = totalSupplyBefore.add(liquidityMinted);

    require(
      balance.mul(_tokenPrice(fundValueAfter, totalSupplyAfter)).div(10**18) >=
        IPoolManagerLogic(poolManagerLogic).minDepositUSD(),
      "must meet minimum deposit"
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
    emitFactoryEvent();
  }

  function withdraw(uint256 _fundTokenAmount) external {
    withdrawTo(msg.sender, _fundTokenAmount);
  }

  /// @notice Withdraw assets based on the fund token amount
  /// @param _fundTokenAmount the fund token amount
  function withdrawTo(address _recipient, uint256 _fundTokenAmount)
    public
    virtual
    nonReentrant
    whenNotFactoryPaused
    whenNotPaused
  {
    require(lastDeposit[msg.sender] < block.timestamp, "can withdraw shortly");
    require(balanceOf(msg.sender) >= _fundTokenAmount, "insufficient balance");

    // Scoping to avoid "stack-too-deep" errors.
    {
      // Calculating how much pool token supply will be left after withdrawal and
      // whether or not this satisfies the min supply (100_000) check.
      // If the user is redeeming all the shares then this check passes.
      // Otherwise, they might have to reduce the amount to be withdrawn.
      uint256 supplyAfter = totalSupply().sub(_fundTokenAmount);
      require(supplyAfter >= 100_000 || supplyAfter == 0, "below supply threshold");
    }

    // calculate the exit fee
    uint256 fundValue = _mintManagerFee();

    // calculate the proportion
    uint256 portion = _fundTokenAmount.mul(10**18).div(totalSupply());

    // first return funded tokens
    _burn(msg.sender, _fundTokenAmount);

    // TODO: Combining into one line to fix stack too deep,
    //       need to refactor some variables into struct in order to have more variables
    IHasSupportedAsset.Asset[] memory _supportedAssets = IHasSupportedAsset(poolManagerLogic).getSupportedAssets();
    WithdrawnAsset[] memory withdrawnAssets = new WithdrawnAsset[](_supportedAssets.length);
    uint16 index = 0;

    for (uint256 i = 0; i < _supportedAssets.length; i++) {
      (address asset, uint256 portionOfAssetBalance, bool externalWithdrawProcessed) = _withdrawProcessing(
        _supportedAssets[i].asset,
        _recipient,
        portion
      );

      if (portionOfAssetBalance > 0) {
        require(asset != address(0), "requires asset to withdraw");
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

    uint256 valueWithdrawn = portion.mul(fundValue).div(10**18);

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
    emitFactoryEvent();
  }

  /// @notice Perform any additional processing on withdrawal of asset
  /// @dev Checks for staked tokens and withdraws them to the investor account
  /// @param asset Asset for withdrawal processing
  /// @param to Investor account to send withdrawed tokens to
  /// @param portion Portion of investor withdrawal of the total dHedge pool
  /// @return withdrawAsset Asset to be withdrawed
  /// @return withdrawBalance Asset balance amount to be withdrawed
  /// @return externalWithdrawProcessed A boolean for success or fail transaction
  function _withdrawProcessing(
    address asset,
    address to,
    uint256 portion
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

    (address withdrawAsset, uint256 withdrawBalance, IAssetGuard.MultiTransaction[] memory transactions) = IAssetGuard(
      guard
    ).withdrawProcessing(address(this), asset, portion, to);

    uint256 txCount = transactions.length;
    if (txCount > 0) {
      uint256 assetBalanceBefore;
      if (withdrawAsset != address(0)) {
        assetBalanceBefore = IERC20Upgradeable(withdrawAsset).balanceOf(address(this));
      }

      for (uint256 i = 0; i < txCount; i++) {
        externalWithdrawProcessed = transactions[i].to.tryAssemblyCall(transactions[i].txData);
      }

      if (withdrawAsset != address(0)) {
        // get any balance increase after withdraw processing and add it to the withdraw balance
        uint256 assetBalanceAfter = IERC20Upgradeable(withdrawAsset).balanceOf(address(this));
        withdrawBalance = withdrawBalance.add(assetBalanceAfter.sub(assetBalanceBefore));
      }
    }

    return (withdrawAsset, withdrawBalance, externalWithdrawProcessed);
  }

  /// @notice Private function to let pool talk to other protocol
  /// @dev execute transaction for the pool
  /// @param to The destination address for pool to talk to
  /// @param data The data that going to send in the transaction
  /// @return success A boolean for success or fail transaction
  function _execTransaction(address to, bytes memory data)
    private
    nonReentrant
    whenNotFactoryPaused
    returns (bool success)
  {
    require(to != address(0), "non-zero address is required");

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
        require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(to), "asset not enabled in pool");
      }
      guard = assetGuard;
      (txType, isPublic) = IGuard(assetGuard).txGuard(poolManagerLogic, to, data);
    }

    require(txType > 0, "invalid transaction");
    // solhint-disable-next-line reason-string
    require(isPublic || msg.sender == manager() || msg.sender == trader(), "only manager or trader or public function");

    success = to.tryAssemblyCall(data);

    // call afterTxGuard to track transactions
    // to make it compatible with previous version, we use low-level call before calling afterTxGuard() function
    // the low level call will return `false` if its execution reverts
    // solhint-disable-next-line avoid-low-level-calls
    (bool hasFunction, bytes memory returnData) = guard.call(abi.encodeWithSignature("isTxTrackingGuard()"));
    if (hasFunction && abi.decode(returnData, (bool))) {
      ITxTrackingGuard(guard).afterTxGuard(poolManagerLogic, to, data);
    }

    emit TransactionExecuted(address(this), manager(), txType, block.timestamp);
    emitFactoryEvent();
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
  /// @return success A boolean indicating if all transactions succeeded
  function execTransactions(TxToExecute[] calldata txs) external returns (bool success) {
    require(txs.length > 0, "no transactions to execute");

    for (uint256 i = 0; i < txs.length; i++) {
      bool result = _execTransaction(txs[i].to, txs[i].data);
      require(result, "transaction failure");
    }

    return true;
  }

  /// @notice Get fund summary of the pool
  /// @return Fund summary of the pool
  function getFundSummary() external view returns (FundSummary memory) {
    (
      uint256 performanceFeeNumerator,
      uint256 managerFeeNumerator,
      uint256 entryFeeNumerator,
      uint256 managerFeeDenominator
    ) = IPoolManagerLogic(poolManagerLogic).getFee();
    (uint256 exitFeeNumerator, uint256 exitFeeDenominator) = IHasFeeInfo(factory).getExitFee();

    return
      FundSummary(
        name(),
        totalSupply(),
        IPoolManagerLogic(poolManagerLogic).totalFundValue(),
        manager(),
        managerName(),
        creationTime,
        privatePool,
        performanceFeeNumerator,
        managerFeeNumerator,
        managerFeeDenominator,
        exitFeeNumerator,
        exitFeeDenominator,
        entryFeeNumerator
      );
  }

  /// @notice Get price of the asset adjusted for any unminted manager fees
  /// @param price A price of the asset
  function tokenPrice() external view returns (uint256 price) {
    (uint256 managerFee, uint256 fundValue) = availableManagerFeeAndTotalFundValue();
    uint256 tokenSupply = totalSupply().add(managerFee);

    price = _tokenPrice(fundValue, tokenSupply);
  }

  function tokenPriceWithoutManagerFee() external view returns (uint256 price) {
    uint256 fundValue = IPoolManagerLogic(poolManagerLogic).totalFundValue();
    uint256 tokenSupply = totalSupply();
    price = _tokenPrice(fundValue, tokenSupply);
  }

  /// @notice Get price of the asset internal call
  /// @param _fundValue The total fund value of the pool
  /// @param _tokenSupply The total token supply of the pool
  /// @return price A price of the asset
  function _tokenPrice(uint256 _fundValue, uint256 _tokenSupply) internal pure returns (uint256 price) {
    if (_tokenSupply == 0 || _fundValue == 0) return 0;
    price = _fundValue.mul(10**18).div(_tokenSupply);
  }

  /// @notice Get available manager fee of the pool
  /// @return fee available manager fee of the pool
  function availableManagerFee() public view returns (uint256 fee) {
    (fee, ) = availableManagerFeeAndTotalFundValue();
  }

  /// @notice Get available manager fee of the pool and totalFundValue
  /// @return fee available manager fee of the pool
  function availableManagerFeeAndTotalFundValue() public view returns (uint256 fee, uint256 fundValue) {
    fundValue = IPoolManagerLogic(poolManagerLogic).totalFundValue();
    uint256 tokenSupply = totalSupply();

    (uint256 performanceFeeNumerator, uint256 managerFeeNumerator, , uint256 managerFeeDenominator) = IPoolManagerLogic(
      poolManagerLogic
    ).getFee();

    fee = _availableManagerFee(
      fundValue,
      tokenSupply,
      performanceFeeNumerator,
      managerFeeNumerator,
      managerFeeDenominator
    );
  }

  /// @notice Get available manager fee of the pool internal call
  /// @param _fundValue The total fund value of the pool
  /// @param _tokenSupply The total token supply of the pool
  /// @param _performanceFeeNumerator The manager fee numerator
  /// @param _managerFeeNumerator The streaming fee numerator
  /// @param _feeDenominator The fee denominator
  /// @return available manager fee of the pool
  function _availableManagerFee(
    uint256 _fundValue,
    uint256 _tokenSupply,
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    uint256 _feeDenominator
  ) internal view returns (uint256 available) {
    if (_tokenSupply == 0 || _fundValue == 0) return 0;

    uint256 currentTokenPrice = _fundValue.mul(10**18).div(_tokenSupply);

    if (currentTokenPrice > tokenPriceAtLastFeeMint) {
      available = currentTokenPrice
        .sub(tokenPriceAtLastFeeMint)
        .mul(_tokenSupply)
        .mul(_performanceFeeNumerator)
        .div(_feeDenominator)
        .div(currentTokenPrice);
    }

    // this timestamp for old pools would be zero at the first time
    if (lastFeeMintTime != 0) {
      uint256 timeChange = block.timestamp.sub(lastFeeMintTime);
      uint256 streamingFee = _tokenSupply.mul(timeChange).mul(_managerFeeNumerator).div(_feeDenominator).div(365 days);
      available = available.add(streamingFee);
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

    (uint256 performanceFeeNumerator, uint256 managerFeeNumerator, , uint256 managerFeeDenominator) = IPoolManagerLogic(
      poolManagerLogic
    ).getFee();

    uint256 available = _availableManagerFee(
      fundValue,
      tokenSupply,
      performanceFeeNumerator,
      managerFeeNumerator,
      managerFeeDenominator
    );

    address daoAddress = IHasDaoInfo(factory).daoAddress();
    uint256 daoFeeNumerator;
    uint256 daoFeeDenominator;

    (daoFeeNumerator, daoFeeDenominator) = IHasDaoInfo(factory).getDaoFee();

    uint256 daoFee = available.mul(daoFeeNumerator).div(daoFeeDenominator);
    uint256 managerFee = available.sub(daoFee);

    if (daoFee > 0) _mint(daoAddress, daoFee);

    if (managerFee > 0) _mint(manager(), managerFee);

    uint256 currentTokenPrice = _tokenPrice(fundValue, tokenSupply);
    if (tokenPriceAtLastFeeMint < currentTokenPrice) {
      tokenPriceAtLastFeeMint = currentTokenPrice;
    }

    lastFeeMintTime = block.timestamp;

    emit ManagerFeeMinted(address(this), manager(), available, daoFee, managerFee, tokenPriceAtLastFeeMint);
    emitFactoryEvent();
  }

  /// @notice Calculate lockup cooldown applied to the investor after pool deposit
  /// @param currentBalance Investor's current pool tokens balance
  /// @param liquidityMinted Liquidity to be minted to investor after pool deposit
  /// @param newCooldown New cooldown lockup time
  /// @param lastCooldown Last cooldown lockup time applied to investor
  /// @param lastDepositTime Timestamp when last pool deposit happened
  /// @param blockTimestamp Timestamp of a block
  /// @return cooldown New lockup cooldown to be applied to investor address
  function calculateCooldown(
    uint256 currentBalance,
    uint256 liquidityMinted,
    uint256 newCooldown,
    uint256 lastCooldown,
    uint256 lastDepositTime,
    uint256 blockTimestamp
  ) public pure returns (uint256 cooldown) {
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
      uint256 additionalCooldown = newCooldown.mul(liquidityMinted).div(currentBalance);
      // Aggregate additional and remaining cooldowns
      uint256 aggregatedCooldown = additionalCooldown.add(remainingCooldown);
      // Resulting value is capped at new cooldown time (shouldn't be bigger) and falls back to one second in case of zero
      cooldown = aggregatedCooldown > newCooldown ? newCooldown : aggregatedCooldown != 0 ? aggregatedCooldown : 1;
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
  function setPoolManagerLogic(address _poolManagerLogic) external returns (bool) {
    require(_poolManagerLogic != address(0), "Invalid poolManagerLogic address");
    require(
      msg.sender == address(factory) || msg.sender == IHasOwnable(factory).owner(),
      "only owner or factory allowed"
    );

    poolManagerLogic = _poolManagerLogic;
    emit PoolManagerLogicSet(_poolManagerLogic, msg.sender);
    return true;
  }

  /// @notice Get address of the manager
  /// @return _manager The address of the manager
  function manager() internal view returns (address _manager) {
    _manager = IManaged(poolManagerLogic).manager();
  }

  /// @notice Get address of the trader
  /// @return _trader The address of the trader
  function trader() internal view returns (address _trader) {
    _trader = IManaged(poolManagerLogic).trader();
  }

  /// @notice Get name of the manager
  /// @return _managerName The name of the manager
  function managerName() public view returns (string memory _managerName) {
    _managerName = IManaged(poolManagerLogic).managerName();
  }

  /// @notice Return boolean if the address is a member of the list
  /// @param member The address of the member
  /// @return True if the address is a member of the list, false otherwise
  function isMemberAllowed(address member) public view returns (bool) {
    return IPoolManagerLogic(poolManagerLogic).isMemberAllowed(member);
  }

  /// @notice execute function of aave flash loan
  /// @dev This function is called after your contract has received the flash loaned amount
  /// @param assets the loaned assets
  /// @param amounts the loaned amounts per each asset
  /// @param premiums the additional owed amount per each asset
  /// @param originator the origin caller address of the flash loan
  /// @param params Variadic packed params to pass to the receiver as extra information
  function executeOperation(
    address[] memory assets,
    uint256[] memory amounts,
    uint256[] memory premiums,
    address originator,
    bytes memory params
  ) external returns (bool success) {
    require(originator == address(this), "only pool flash loan origin");

    address aaveLendingPoolAssetGuard = IHasGuardInfo(factory).getAssetGuard(msg.sender);
    require(
      aaveLendingPoolAssetGuard != address(0) &&
        msg.sender == IAaveLendingPoolAssetGuard(aaveLendingPoolAssetGuard).aaveLendingPool(),
      "invalid lending pool"
    );

    (uint256[] memory interestRateModes, uint256 portion) = abi.decode(params, (uint256[], uint256));

    address weth = IHasGuardInfo(factory).getAddress("weth");
    uint256 wethBalanceBefore = IERC20Upgradeable(weth).balanceOf(address(this));

    IAssetGuard.MultiTransaction[] memory transactions = IAaveLendingPoolAssetGuard(aaveLendingPoolAssetGuard)
      .flashloanProcessing(address(this), portion, assets, amounts, premiums, interestRateModes);

    for (uint256 i = 0; i < transactions.length; i++) {
      success = transactions[i].to.tryAssemblyCall(transactions[i].txData);
    }

    // Liquidation of collateral not enough to pay off debt, flashloan repayment stealing pool's weth
    require(
      wethBalanceBefore == 0 || wethBalanceBefore <= IERC20Upgradeable(weth).balanceOf(address(this)),
      "too high slippage"
    );
  }

  /// @notice Emits an event through the factory, so we can just listen to the factory offchain
  function emitFactoryEvent() internal {
    IPoolFactory(factory).emitPoolEvent();
  }

  /// @notice Support safeTransfers from ERC721 asset contracts
  /// @dev Currently used for Synthetix V3
  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) external override returns (bytes4 magicSelector) {
    address contractGuard = IHasGuardInfo(factory).getContractGuard(operator);

    // Only guarded contract can initiate ERC721 transfers
    require(contractGuard != address(0), "only guarded address allowed");

    require(
      IERC721VerifyingGuard(contractGuard).verifyERC721(operator, from, tokenId, data),
      "ERC721 token not verified"
    );

    magicSelector = IERC721ReceiverUpgradeable.onERC721Received.selector;
  }

  uint256[47] private __gap;
}
