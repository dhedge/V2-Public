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

pragma solidity 0.6.12;

import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IHasFeeInfo.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IHasPausable.sol";
import "./interfaces/IPoolManagerLogic.sol";
import "./interfaces/IManaged.sol";
import "./utils/TxDataUtils.sol";
import "./guards/IGuard.sol";
import "./guards/ILPAssetGuard.sol";

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";

contract PoolLogic is ERC20UpgradeSafe, ReentrancyGuardUpgradeSafe, TxDataUtils {
  using SafeMath for uint256;

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

  function totalFundValue() public view virtual returns (uint256) {
    uint256 total = 0;
    IPoolManagerLogic dm = IPoolManagerLogic(poolManagerLogic);
    address[] memory _supportedAssets = dm.getSupportedAssets();
    uint256 assetCount = _supportedAssets.length;

    for (uint256 i = 0; i < assetCount; i++) {
      total = total.add(dm.assetValue(_supportedAssets[i]));
    }
    return total;
  }

  function deposit(address _asset, uint256 _amount) public onlyPrivate whenNotPaused returns (uint256) {
    require(IPoolManagerLogic(poolManagerLogic).isDepositAsset(_asset), "invalid deposit asset");

    lastDeposit[msg.sender] = block.timestamp;

    uint256 fundValue = _mintManagerFee();

    uint256 totalSupplyBefore = totalSupply();

    require(IERC20(_asset).transferFrom(msg.sender, address(this), _amount), "token transfer failed");

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

    IPoolManagerLogic dm = IPoolManagerLogic(poolManagerLogic);
    address[] memory _supportedAssets = dm.getSupportedAssets();
    uint256 assetCount = _supportedAssets.length;

    for (uint256 i = 0; i < assetCount; i++) {
      address asset = _supportedAssets[i];
      uint256 totalAssetBalance = IERC20(asset).balanceOf(address(this));
      uint256 portionOfAssetBalance = totalAssetBalance.mul(portion).div(10**18);

      if (portionOfAssetBalance > 0) {
        // Ignoring return value for transfer as want to transfer no matter what happened
        IERC20(asset).transfer(msg.sender, portionOfAssetBalance);
        _withdrawProcessing(asset, msg.sender, portion);
      }
    }

    uint256 valueWithdrawn = portion.mul(fundValue).div(10**18);

    emit Withdrawal(
      address(this),
      msg.sender,
      valueWithdrawn,
      _fundTokenAmount,
      balanceOf(msg.sender),
      totalFundValue(),
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
    uint8 assetType = IHasAssetInfo(factory).getAssetType(asset);

    if (assetType == 2) {
      // Sushi LP token - withdraw any staked tokens
      address guard = IHasGuardInfo(factory).getGuard(to);
      require(guard != address(0), "invalid guard");
      (address stakingContract, bytes memory txData) =
        ILPAssetGuard(guard).getWithdrawStakedTx(address(this), asset, portion, msg.sender);
      if (txData.length > 1) {
        (bool success, ) = stakingContract.call(txData);
        require(success == true, "failed to withdraw staked tokens");
      }
    }
  }

  function execTransaction(address to, bytes memory data) public onlyManagerOrTrader whenNotPaused returns (bool) {
    require(to != address(0), "non-zero address is required");

    address guard = IHasGuardInfo(factory).getGuard(to);

    require(guard != address(0), "invalid destination");

    if (IHasAssetInfo(factory).isValidAsset(to)) {
      require(IPoolManagerLogic(poolManagerLogic).isSupportedAsset(to), "asset not enabled in pool");
    }

    // to pass the guard, the data must return a transaction type. refer to header for transaction types
    uint8 txType = IGuard(guard).txGuard(poolManagerLogic, data);
    require(txType > 0, "invalid transaction");

    (bool success, ) = to.call(data);
    require(success == true, "failed to execute the call");

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
      totalFundValue(),
      manager(),
      managerName(),
      creationTime,
      privatePool,
      managerFeeNumerator,
      managerFeeDenominator
    );
  }

  function tokenPrice() public view returns (uint256) {
    uint256 fundValue = totalFundValue();
    uint256 tokenSupply = totalSupply();

    return _tokenPrice(fundValue, tokenSupply);
  }

  function _tokenPrice(uint256 _fundValue, uint256 _tokenSupply) internal pure returns (uint256) {
    if (_tokenSupply == 0 || _fundValue == 0) return 0;

    return _fundValue.mul(10**18).div(_tokenSupply);
  }

  function availableManagerFee() public view returns (uint256) {
    uint256 fundValue = totalFundValue();
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
    fundValue = totalFundValue();
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
