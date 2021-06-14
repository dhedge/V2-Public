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
// MIT License
// ===========
//
// Copyright (c) 2020 dHEDGE DAO
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

// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IHasFeeInfo.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IHasPausable.sol";
import "./interfaces/IPoolManagerLogic.sol";
import "./interfaces/IHasSupportedAsset.sol";
import "./interfaces/IManaged.sol";
import "./guards/IGuard.sol";
import "./guards/IAssetGuard.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract PoolLogic is ERC20Upgradeable, ReentrancyGuardUpgradeable {
  using SafeMathUpgradeable for uint256;

  event Deposit(
    address fundAddress,
    address investor,
    address assetDeposited,
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
    uint256 time
  );
  event TransactionExecuted(address pool, address manager, uint8 transactionType, uint256 time);

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

  modifier onlyPrivate() {
    require(msg.sender == manager() || !privatePool || isMemberAllowed(msg.sender), "only members allowed");
    _;
  }

  modifier onlyManager() {
    require(msg.sender == manager(), "only manager");
    _;
  }

  modifier onlyManagerOrTrader() {
    require(msg.sender == manager() || msg.sender == trader(), "only manager or trader");
    _;
  }

  modifier whenNotPaused() {
    require(!IHasPausable(factory).isPaused(), "contracts paused");
    _;
  }

  function initialize(
    address _factory,
    bool _privatePool,
    string memory _fundName,
    string memory _fundSymbol
  ) public initializer {
    require(_factory != address(0), "Invalid factory");
    __ERC20_init(_fundName, _fundSymbol);
    __ReentrancyGuard_init();

    factory = _factory;
    _setPoolPrivacy(_privatePool);
    creator = msg.sender;
    creationTime = block.timestamp;

    tokenPriceAtLastFeeMint = 10**18;
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override {
    super._beforeTokenTransfer(from, to, amount);

    require(getExitRemainingCooldown(from) == 0, "cooldown active");
  }

  function setPoolPrivate(bool _privatePool) public onlyManager {
    require(privatePool != _privatePool, "flag must be different");

    _setPoolPrivacy(_privatePool);
  }

  function _setPoolPrivacy(bool _privacy) internal {
    privatePool = _privacy;

    emit PoolPrivacyUpdated(_privacy);
  }

  function deposit(address _asset, uint256 _amount) public onlyPrivate whenNotPaused returns (uint256) {
    require(IPoolManagerLogic(poolManagerLogic).isDepositAsset(_asset), "invalid deposit asset");

    lastDeposit[msg.sender] = block.timestamp;

    uint256 fundValue = _mintManagerFee();

    uint256 totalSupplyBefore = totalSupply();

    require(IERC20Upgradeable(_asset).transferFrom(msg.sender, address(this), _amount), "token transfer failed");

    uint256 usdAmount = IPoolManagerLogic(poolManagerLogic).assetValue(_asset, _amount);

    uint256 liquidityMinted;
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
      usdAmount,
      liquidityMinted,
      balanceOf(msg.sender),
      fundValue.add(usdAmount),
      totalSupplyBefore.add(liquidityMinted),
      block.timestamp
    );

    return liquidityMinted;
  }

  function withdraw(uint256 _fundTokenAmount) public virtual nonReentrant whenNotPaused {
    require(balanceOf(msg.sender) >= _fundTokenAmount, "insufficient balance");

    require(getExitRemainingCooldown(msg.sender) == 0, "cooldown active");

    uint256 fundValue = _mintManagerFee();

    //calculate the proportion
    uint256 portion = _fundTokenAmount.mul(10**18).div(totalSupply());

    //first return funded tokens
    _burn(msg.sender, _fundTokenAmount);

    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogic);
    IHasSupportedAsset.Asset[] memory _supportedAssets = poolManagerLogicAssets.getSupportedAssets();
    uint256 assetCount = _supportedAssets.length;

    for (uint256 i = 0; i < assetCount; i++) {
      address asset = _supportedAssets[i].asset;
      uint256 totalAssetBalance = IERC20Upgradeable(asset).balanceOf(address(this));
      uint256 portionOfAssetBalance = totalAssetBalance.mul(portion).div(10**18);

      if (portionOfAssetBalance > 0) {
        // Ignoring return value for transfer as want to transfer no matter what happened
        IERC20Upgradeable(asset).transfer(msg.sender, portionOfAssetBalance);
      }
      _withdrawProcessing(asset, msg.sender, portion);
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
      block.timestamp
    );
  }

  /// @notice Perform any additional processing on withdrawal of asset
  /// @dev Checks for staked tokens and withdraws them to the investor account
  /// @param asset Asset for withdrawal processing
  /// @param to Investor account to send withdrawed tokens to
  /// @param portion Portion of investor withdrawal of the total dHedge pool
  function _withdrawProcessing(
    address asset,
    address to,
    uint256 portion
  ) internal {
    // Withdraw any external tokens (eg. staked tokens in other contracts)
    address guard = IHasGuardInfo(factory).getGuard(asset);
    require(guard != address(0), "invalid guard");
    (address stakingContract, bytes memory txData) =
      IAssetGuard(guard).getWithdrawStakedTx(address(this), asset, portion, to);
    if (txData.length > 1) {
      (bool success, ) = stakingContract.call(txData);
      require(success, "failed to withdraw staked tokens");
    }
  }

  /// @notice Function to let pool talk to other protocol
  /// @dev execute transaction for the pool
  /// @param to The destination address for pool to talk to
  /// @param data The data that going to send in the transaction
  /// @return A boolean for success or fail transaction
  function execTransaction(address to, bytes memory data)
    public
    onlyManagerOrTrader
    nonReentrant
    whenNotPaused
    returns (bool)
  {
    require(to != address(0), "non-zero address is required");

    address guard = IHasGuardInfo(factory).getGuard(to);

    require(guard != address(0), "invalid destination");

    if (IHasAssetInfo(factory).isValidAsset(to)) {
      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(to), "asset not enabled in pool");
    }

    // to pass the guard, the data must return a transaction type. refer to header for transaction types
    uint8 txType = IGuard(guard).txGuard(poolManagerLogic, to, data);
    require(txType > 0, "invalid transaction");

    (bool success, ) = to.call(data);
    require(success, "failed to execute the call");

    emit TransactionExecuted(address(this), manager(), txType, block.timestamp);

    return true;
  }

  function getFundSummary()
    public
    view
    returns (
      string memory,
      uint256,
      uint256,
      address,
      string memory,
      uint256,
      bool,
      uint256,
      uint256
    )
  {
    uint256 managerFeeNumerator;
    uint256 managerFeeDenominator;
    (managerFeeNumerator, managerFeeDenominator) = IHasFeeInfo(factory).getPoolManagerFee(address(this));

    return (
      name(),
      totalSupply(),
      IPoolManagerLogic(poolManagerLogic).totalFundValue(),
      manager(),
      managerName(),
      creationTime,
      privatePool,
      managerFeeNumerator,
      managerFeeDenominator
    );
  }

  function tokenPrice() public view returns (uint256) {
    uint256 fundValue = IPoolManagerLogic(poolManagerLogic).totalFundValue();
    uint256 tokenSupply = totalSupply();

    return _tokenPrice(fundValue, tokenSupply);
  }

  function _tokenPrice(uint256 _fundValue, uint256 _tokenSupply) internal pure returns (uint256) {
    if (_tokenSupply == 0 || _fundValue == 0) return 0;

    return _fundValue.mul(10**18).div(_tokenSupply);
  }

  function availableManagerFee() public view returns (uint256) {
    uint256 fundValue = IPoolManagerLogic(poolManagerLogic).totalFundValue();
    uint256 tokenSupply = totalSupply();

    uint256 managerFeeNumerator;
    uint256 managerFeeDenominator;
    (managerFeeNumerator, managerFeeDenominator) = IHasFeeInfo(factory).getPoolManagerFee(address(this));

    return
      _availableManagerFee(fundValue, tokenSupply, tokenPriceAtLastFeeMint, managerFeeNumerator, managerFeeDenominator);
  }

  function _availableManagerFee(
    uint256 _fundValue,
    uint256 _tokenSupply,
    uint256 _lastFeeMintPrice,
    uint256 _feeNumerator,
    uint256 _feeDenominator
  ) internal pure returns (uint256) {
    if (_tokenSupply == 0 || _fundValue == 0) return 0;

    uint256 currentTokenPrice = _fundValue.mul(10**18).div(_tokenSupply);

    if (currentTokenPrice <= _lastFeeMintPrice) return 0;

    uint256 available =
      currentTokenPrice.sub(_lastFeeMintPrice).mul(_tokenSupply).mul(_feeNumerator).div(_feeDenominator).div(
        currentTokenPrice
      );

    return available;
  }

  function mintManagerFee() public whenNotPaused {
    _mintManagerFee();
  }

  function _mintManagerFee() internal returns (uint256 fundValue) {
    fundValue = IPoolManagerLogic(poolManagerLogic).totalFundValue();
    uint256 tokenSupply = totalSupply();

    uint256 managerFeeNumerator;
    uint256 managerFeeDenominator;
    (managerFeeNumerator, managerFeeDenominator) = IHasFeeInfo(factory).getPoolManagerFee(address(this));

    uint256 available =
      _availableManagerFee(fundValue, tokenSupply, tokenPriceAtLastFeeMint, managerFeeNumerator, managerFeeDenominator);

    // Ignore dust when minting performance fees
    if (available < 10000) return fundValue;

    address daoAddress = IHasDaoInfo(factory).getDaoAddress();
    uint256 daoFeeNumerator;
    uint256 daoFeeDenominator;

    (daoFeeNumerator, daoFeeDenominator) = IHasDaoInfo(factory).getDaoFee();

    uint256 daoFee = available.mul(daoFeeNumerator).div(daoFeeDenominator);
    uint256 managerFee = available.sub(daoFee);

    if (daoFee > 0) _mint(daoAddress, daoFee);

    if (managerFee > 0) _mint(manager(), managerFee);

    tokenPriceAtLastFeeMint = _tokenPrice(fundValue, tokenSupply);

    emit ManagerFeeMinted(address(this), manager(), available, daoFee, managerFee, tokenPriceAtLastFeeMint);
  }

  function getExitCooldown() public view returns (uint256) {
    return IHasFeeInfo(factory).getExitCooldown();
  }

  function getExitRemainingCooldown(address sender) public view returns (uint256) {
    uint256 cooldown = getExitCooldown();
    uint256 cooldownFinished = lastDeposit[sender].add(cooldown);

    if (cooldownFinished < block.timestamp) return 0;

    return cooldownFinished.sub(block.timestamp);
  }

  function setPoolManagerLogic(address _poolManagerLogic) external returns (bool) {
    require(_poolManagerLogic != address(0), "Invalid poolManagerLogic address");
    require(
      msg.sender == address(factory) || msg.sender == IHasDaoInfo(factory).getDaoAddress(),
      "only DAO or factory allowed"
    );

    poolManagerLogic = _poolManagerLogic;
    emit PoolManagerLogicSet(_poolManagerLogic, msg.sender);
    return true;
  }

  function manager() internal view returns (address) {
    return IManaged(poolManagerLogic).manager();
  }

  function trader() internal view returns (address) {
    return IManaged(poolManagerLogic).trader();
  }

  function managerName() public view returns (string memory) {
    return IManaged(poolManagerLogic).managerName();
  }

  function isMemberAllowed(address member) public view returns (bool) {
    return IManaged(poolManagerLogic).isMemberAllowed(member);
  }

  uint256[50] private __gap;
}
