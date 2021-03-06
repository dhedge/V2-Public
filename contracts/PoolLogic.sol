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
// Transaction Types in execTransaction()
// 1. Approve: Approving a token for spending by different address/contract
// 2. Exchange: Exchange/trade of tokens eg. Uniswap, Synthetix
// 3. AddLiquidity: Add liquidity of Uniswap, Sushiswap
// 4. RemoveLiquidity: Remove liquidity of Uniswap, Sushiswap
// 5. Stake: Stake tokens into a third party contract (eg. Sushi yield farming)
// 6. Unstake: Unstake tokens from a third party contract (eg. Sushi yield farming)
// 7. Claim: Claim rewards tokens from a third party contract (eg. SUSHI & MATIC rewards)
// 8. UnstakeAndClaim: Unstake tokens and claim rewards from a third party contract
// 9. Deposit: Aave deposit tokens -> get Aave Interest Bearing Token
// 10. Withdraw: Withdraw tokens from Aave Interest Bearing Token
// 11. SetUserUseReserveAsCollateral: Aave set reserve asset to be used as collateral
// 12. Borrow: Aave borrow tokens
// 13. Repay: Aave repay tokens
// 14. SwapBorrowRateMode: Aave change borrow rate mode (stable/variable)
// 15. RebalanceStableBorrowRate: Aave rebalance stable borrow rate
// 16. JoinPool: Balancer join pool
// 17. ExitPool: Balancer exit pool
// 18. Deposit: EasySwapper Deposit
// 19. Withdraw: EasySwapper Withdraw
// 20. Mint: Uniswap V3 Mint position
// 21. IncreaseLiquidity: Uniswap V3 increase liquidity position
// 22. DecreaseLiquidity: Uniswap V3 decrease liquidity position
// 23. Burn: Uniswap V3 Burn position
// 24. Collect: Uniswap V3 collect fees
// 25. Multicall: Uniswap V3 Multicall

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
import "./interfaces/IPoolPerformance.sol";
import "./interfaces/IHasSupportedAsset.sol";
import "./interfaces/IHasPoolPerformance.sol";
import "./interfaces/IHasOwnable.sol";
import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IManaged.sol";
import "./interfaces/guards/IGuard.sol";
import "./interfaces/guards/IAssetGuard.sol";
import "./interfaces/guards/IAaveLendingPoolAssetGuard.sol";
import "./utils/AddressHelper.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @notice Logic implementation for pool
contract PoolLogic is ERC20Upgradeable, ReentrancyGuardUpgradeable {
  using SafeMathUpgradeable for uint256;
  using AddressHelper for address;

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

  modifier onlyPrivate() {
    require(msg.sender == manager() || !privatePool || isMemberAllowed(msg.sender), "only members allowed");
    _;
  }

  modifier onlyManager() {
    require(msg.sender == manager(), "only manager");
    _;
  }

  modifier whenNotPaused() {
    require(!IHasPausable(factory).isPaused(), "contracts paused");
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
    IPoolPerformance(IHasPoolPerformance(factory).poolPerformanceAddress()).initializePool();
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

    bool isWhitelisted = IPoolFactory(factory).transferWhitelist(from);

    if (isWhitelisted) {
      lastWhitelistTransfer[to] = block.timestamp;
      return;
    }

    // Users that receive tokens from a whitelisted source cannot withdraw, or transfer them on, for 5 minutes
    require(lastWhitelistTransfer[from].add(5 minutes) < block.timestamp, "whitelist cooldown active");
    require(getExitRemainingCooldown(from) == 0, "cooldown active");
  }

  /// @notice Set the pool privacy
  /// @param _privatePool true if the pool is private, false otherwise
  function setPoolPrivate(bool _privatePool) external onlyManager {
    require(privatePool != _privatePool, "flag must be different");

    _setPoolPrivacy(_privatePool);
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
  function deposit(address _asset, uint256 _amount)
    external
    onlyPrivate
    whenNotPaused
    returns (uint256 liquidityMinted)
  {
    require(IPoolManagerLogic(poolManagerLogic).isDepositAsset(_asset), "invalid deposit asset");

    lastDeposit[msg.sender] = block.timestamp;

    uint256 fundValue = _mintManagerFee();

    uint256 totalSupplyBefore = totalSupply();

    _asset.tryAssemblyCall(
      abi.encodeWithSelector(IERC20Upgradeable.transferFrom.selector, msg.sender, address(this), _amount)
    );

    IPoolPerformance(IHasPoolPerformance(factory).poolPerformanceAddress()).changeAssetBalance(_asset, _amount, 0);

    uint256 usdAmount = IPoolManagerLogic(poolManagerLogic).assetValue(_asset, _amount);

    if (totalSupplyBefore > 0) {
      //total balance converted to susd that this contract holds
      //need to calculate total value of synths in this contract
      liquidityMinted = usdAmount.mul(totalSupplyBefore).div(fundValue);
    } else {
      liquidityMinted = usdAmount;
    }

    _mint(msg.sender, liquidityMinted);

    emit Deposit(
      address(this),
      msg.sender,
      _asset,
      _amount,
      usdAmount,
      liquidityMinted,
      balanceOf(msg.sender),
      fundValue.add(usdAmount),
      totalSupplyBefore.add(liquidityMinted),
      block.timestamp
    );
  }

  function withdraw(uint256 _fundTokenAmount) external {
    withdrawTo(msg.sender, _fundTokenAmount);
  }

  /// @notice Withdraw assets based on the fund token amount
  /// @param _fundTokenAmount the fund token amount
  function withdrawTo(address _recipient, uint256 _fundTokenAmount) public virtual nonReentrant whenNotPaused {
    require(lastDeposit[msg.sender] < block.timestamp, "can withdraw shortly");
    require(balanceOf(msg.sender) >= _fundTokenAmount, "insufficient balance");

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

    IPoolPerformance poolPerformance = IPoolPerformance(IHasPoolPerformance(factory).poolPerformanceAddress());
    // We must now update our internal balances to whatever the result of the withdraw
    if (totalSupply() == 0) {
      poolPerformance.resetInternalValueFactor();
    }

    poolPerformance.updateInternalBalances();

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
  }

  /// @notice Withdraw single asset based on the fund token amounts
  /// @param _fundTokenAmount the fund token amount
  /// @param _asset the withdraw asset address
  function withdrawSingle(uint256 _fundTokenAmount, address _asset) external virtual nonReentrant whenNotPaused {
    require(lastDeposit[msg.sender] < block.timestamp, "can withdraw shortly");
    require(balanceOf(msg.sender) >= _fundTokenAmount, "insufficient balance");
    require(IPoolManagerLogic(poolManagerLogic).isDepositAsset(_asset), "invalid deposit asset");

    uint256 fundValue = _mintManagerFee();

    uint256 exitFee;
    // If withdrawing all existing tokens, no need to pay fee.
    if (_fundTokenAmount == totalSupply()) {
      exitFee = 0;
    } else {
      (uint256 exitFeeNumerator, uint256 exitFeeDenominator) = IHasFeeInfo(factory).getExitFee();
      exitFee = _fundTokenAmount.mul(exitFeeNumerator).div(exitFeeDenominator);
    }

    // calculate the proportion
    uint256 portion = _fundTokenAmount.sub(exitFee).mul(10**18).div(totalSupply());
    // first return funded tokens
    _burn(msg.sender, _fundTokenAmount);

    uint256 valueWithdrawn = fundValue.mul(portion).div(10**18);
    uint256 assetPrice = IHasAssetInfo(factory).getAssetPrice(_asset);
    uint256 withdrawAmount = valueWithdrawn.mul(10**IERC20Extended(_asset).decimals()).div(assetPrice);

    require(IERC20Upgradeable(_asset).balanceOf(address(this)) >= withdrawAmount, "insufficient asset amount");
    _asset.tryAssemblyCall(abi.encodeWithSelector(IERC20Upgradeable.transfer.selector, msg.sender, withdrawAmount));

    WithdrawnAsset[] memory withdrawnAssets = new WithdrawnAsset[](1);
    withdrawnAssets[0] = WithdrawnAsset({asset: _asset, amount: withdrawAmount, externalWithdrawProcessed: false});

    IPoolPerformance(IHasPoolPerformance(factory).poolPerformanceAddress()).changeAssetBalance(
      _asset,
      0,
      withdrawAmount
    );

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
  }

  function getWithdrawSingleMax(address _asset) external view returns (uint256 fundTokenAmount) {
    uint256 fundValue = IPoolManagerLogic(poolManagerLogic).totalFundValue();
    uint256 assetValue = IPoolManagerLogic(poolManagerLogic).assetValue(_asset);
    uint256 tokenSupply = totalSupply();
    // TODO: check streaming fee
    (uint256 performanceFeeNumerator, uint256 managerFeeNumerator, uint256 managerFeeDenominator) = IPoolManagerLogic(
      poolManagerLogic
    ).getFee();

    uint256 availableFee = _availableManagerFee(
      fundValue,
      tokenSupply,
      performanceFeeNumerator,
      managerFeeNumerator,
      managerFeeDenominator
    );

    (uint256 exitFeeNumerator, uint256 exitFeeDenominator) = IHasFeeInfo(factory).getExitFee();

    fundTokenAmount = assetValue.mul(tokenSupply.add(availableFee)).div(fundValue).mul(exitFeeDenominator).div(
      exitFeeDenominator.sub(exitFeeNumerator)
    );
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
        // calculated the balance change after withdraw process.
        uint256 assetBalanceAfter = IERC20Upgradeable(withdrawAsset).balanceOf(address(this));
        withdrawBalance = withdrawBalance.add(assetBalanceAfter.sub(assetBalanceBefore));
      }
    }

    return (withdrawAsset, withdrawBalance, externalWithdrawProcessed);
  }

  /// @notice Function to let pool talk to other protocol
  /// @dev execute transaction for the pool
  /// @param to The destination address for pool to talk to
  /// @param data The data that going to send in the transaction
  /// @return success A boolean for success or fail transaction
  function execTransaction(address to, bytes memory data) external nonReentrant whenNotPaused returns (bool success) {
    require(to != address(0), "non-zero address is required");

    IPoolPerformance poolPerformance = IPoolPerformance(IHasPoolPerformance(factory).poolPerformanceAddress());
    poolPerformance.recordExternalValue(address(this));

    address contractGuard = IHasGuardInfo(factory).getContractGuard(to);
    address assetGuard = IHasGuardInfo(factory).getAssetGuard(to);

    uint16 txType;
    bool isPublic;
    if (contractGuard != address(0)) {
      (txType, isPublic) = IGuard(contractGuard).txGuard(poolManagerLogic, to, data);
    } else {
      require(assetGuard != address(0), "Guard not found");
      // only asset guard is available
      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(to), "asset not enabled in pool");
    }

    if (txType == 0 && assetGuard != address(0)) {
      // contract guard is not available
      (txType, isPublic) = IGuard(assetGuard).txGuard(poolManagerLogic, to, data);
    }

    require(txType > 0, "invalid transaction");
    // solhint-disable-next-line reason-string
    require(isPublic || msg.sender == manager() || msg.sender == trader(), "only manager or trader or public function");

    success = to.tryAssemblyCall(data);

    // We must now update our internal balances to whatever the result of this tx is
    poolPerformance.updateInternalBalances();

    emit TransactionExecuted(address(this), manager(), txType, block.timestamp);
  }

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
  }

  /// @notice Get fund summary of the pool
  /// @return Fund summary of the pool
  function getFundSummary() external view returns (FundSummary memory) {
    (uint256 performanceFeeNumerator, uint256 managerFeeNumerator, uint256 managerFeeDenominator) = IPoolManagerLogic(
      poolManagerLogic
    ).getFee();
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
        exitFeeDenominator
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

    (uint256 performanceFeeNumerator, uint256 managerFeeNumerator, uint256 managerFeeDenominator) = IPoolManagerLogic(
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
  function mintManagerFee() external whenNotPaused {
    _mintManagerFee();
  }

  /// @notice Get mint manager fee of the pool internal call
  /// @return fundValue The total fund value of the pool
  function _mintManagerFee() internal returns (uint256 fundValue) {
    // This has to run on deposit
    IPoolPerformance(IHasPoolPerformance(factory).poolPerformanceAddress()).recordExternalValue(address(this));

    fundValue = IPoolManagerLogic(poolManagerLogic).totalFundValue();
    uint256 tokenSupply = totalSupply();

    (uint256 performanceFeeNumerator, uint256 managerFeeNumerator, uint256 managerFeeDenominator) = IPoolManagerLogic(
      poolManagerLogic
    ).getFee();

    uint256 available = _availableManagerFee(
      fundValue,
      tokenSupply,
      performanceFeeNumerator,
      managerFeeNumerator,
      managerFeeDenominator
    );

    // Ignore dust when minting performance fees
    if (available < 10000) return fundValue;

    address daoAddress = IHasDaoInfo(factory).daoAddress();
    uint256 daoFeeNumerator;
    uint256 daoFeeDenominator;

    (daoFeeNumerator, daoFeeDenominator) = IHasDaoInfo(factory).getDaoFee();

    uint256 daoFee = available.mul(daoFeeNumerator).div(daoFeeDenominator);
    uint256 managerFee = available.sub(daoFee);

    if (daoFee > 0) _mint(daoAddress, daoFee);

    if (managerFee > 0) _mint(manager(), managerFee);

    tokenPriceAtLastFeeMint = _tokenPrice(fundValue, tokenSupply);
    lastFeeMintTime = block.timestamp;

    emit ManagerFeeMinted(address(this), manager(), available, daoFee, managerFee, tokenPriceAtLastFeeMint);
  }

  /// @notice Get exit cooldown of the pool
  /// @return exitCooldown The exit cooldown of the pool
  function getExitCooldown() public view returns (uint256 exitCooldown) {
    exitCooldown = IHasFeeInfo(factory).getExitCooldown();
  }

  /// @notice Get exit remaining time of the pool
  /// @return remaining The remaining exit time of the pool
  function getExitRemainingCooldown(address sender) public view returns (uint256 remaining) {
    uint256 cooldown = getExitCooldown();
    uint256 cooldownFinished = lastDeposit[sender].add(cooldown);

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

  uint256[48] private __gap;
}
