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

// Deprecated
// import "./IExchanger.sol";
// import "./interfaces/IAddressResolver.sol";
// import "./interfaces/ISystemStatus.sol";
import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IHasFeeInfo.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IHasPausable.sol";
import "./interfaces/IPoolManagerLogic.sol";
import "./interfaces/IManaged.sol";
import "./utils/TxDataUtils.sol";
import "./guards/IGuard.sol";

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";

contract PoolLogic is ERC20UpgradeSafe, ReentrancyGuardUpgradeSafe, TxDataUtils {
  using SafeMath for uint256;

  // Deprecated
  // bytes32 constant private _EXCHANGER_KEY = "Exchanger";
  // bytes32 private constant _SYSTEM_STATUS_KEY = "SystemStatus";
  // bytes32 private constant _SUSD_KEY = "sUSD";

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

  // Deprecated
  // IAddressResolver public addressResolver;

  address public factory;

  // Deprecated
  // bytes32[] public supportedAssets;

  // Deprecated
  // mapping(bytes32 => uint256) public assetPosition; // maps the asset to its 1-based position (Deprecated)

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

  // Deprecated
  // function _settleAll() internal {
  //     ISynthetix sx = ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY));

  //     uint256 assetCount = supportedAssets.length;

  //     for (uint256 i = 0; i < assetCount; i++) {

  //         address proxy = getAssetProxy(supportedAssets[i]);
  //         uint256 totalAssetBalance = IERC20(proxy).balanceOf(address(this));

  //         if (totalAssetBalance > 0)
  //             sx.settle(supportedAssets[i]);

  //     }
  // }

  // Deprecated
  // function _settleNotSuspended() internal {
  //     ISynthetix sx = ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY));
  //     ISystemStatus status = ISystemStatus(addressResolver.getAddress(_SYSTEM_STATUS_KEY));

  //     uint256 assetCount = supportedAssets.length;

  //     for (uint256 i = 0; i < assetCount; i++) {
  //         try status.requireSynthActive(supportedAssets[i]) {

  //             address proxy = getAssetProxy(supportedAssets[i]);
  //             uint256 totalAssetBalance = IERC20(proxy).balanceOf(address(this));

  //             if (totalAssetBalance > 0)
  //                 sx.settle(supportedAssets[i]);

  //         } catch {
  //             continue;
  //         }
  //     }
  // }

  // Deprecated
  // function forfeitSuspendedSynthsAndWithdraw(uint256 _fundTokenAmount) public virtual {
  //     _withdraw(_fundTokenAmount, true);
  // }

  function withdraw(uint256 _fundTokenAmount) public virtual nonReentrant whenNotPaused {
    require(balanceOf(msg.sender) >= _fundTokenAmount, "insufficient balance");

    require(getExitRemainingCooldown(msg.sender) == 0, "cooldown active");

    // Deprecated
    //calculate the exit fee and transfer to the DAO in pool tokens
    // uint256 exitFeeNumerator;
    // uint256 exitFeeDenominator;

    // if (getExitFeeRemainingCooldown(msg.sender) > 0) {
    //     (exitFeeNumerator, exitFeeDenominator) = IHasFeeInfo(factory).getExitFee();
    // } else {
    //     exitFeeNumerator = 0;
    //     exitFeeDenominator = 1;
    // }

    // uint256 daoExitFee = _fundTokenAmount.mul(exitFeeNumerator).div(exitFeeDenominator);

    // uint256 lastDepositTemp = lastDeposit[msg.sender];
    // lastDeposit[msg.sender] = 0;

    // if (daoExitFee > 0) {
    //     address daoAddress = IHasDaoInfo(factory).getDaoAddress();

    //     _transfer(msg.sender, daoAddress, daoExitFee);
    // }

    // Deprecated
    // we need to settle all the assets before determining the total fund value
    // if(_forfeitSuspendedSynths){
    //     _settleNotSuspended();
    // } else {
    //     _settleAll();
    // }

    // Deprecated
    // _mintManagerFee(false);
    uint256 fundValue = _mintManagerFee();

    //calculate the proportion
    // _fundTokenAmount = _fundTokenAmount.sub(daoExitFee);
    uint256 portion = _fundTokenAmount.mul(10**18).div(totalSupply());

    //first return funded tokens
    _burn(msg.sender, _fundTokenAmount);

    IPoolManagerLogic dm = IPoolManagerLogic(poolManagerLogic);
    address[] memory _supportedAssets = dm.getSupportedAssets();
    uint256 assetCount = _supportedAssets.length;

    // _forfeitSuspendedSynths deprecated
    for (uint256 i = 0; i < assetCount; i++) {
      address asset = _supportedAssets[i];
      uint256 totalAssetBalance = IERC20(asset).balanceOf(address(this));
      uint256 portionOfAssetBalance = totalAssetBalance.mul(portion).div(10**18);

      if (portionOfAssetBalance > 0) {
        // Ignoring return value for transfer as want to transfer no matter what happened
        IERC20(asset).transfer(msg.sender, portionOfAssetBalance);
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
  // uint256,
  // uint256
  {
    uint256 managerFeeNumerator;
    uint256 managerFeeDenominator;
    (managerFeeNumerator, managerFeeDenominator) = IHasFeeInfo(factory).getPoolManagerFee(address(this));

    // uint256 exitNumerator;
    // uint256 exitDenominator;
    // (exitNumerator, exitDenominator) = IHasFeeInfo(factory).getExitFee();

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
      // exitNumerator,
      // exitDenominator
    );
  }

  // Deprecated
  // function getWaitingPeriods()
  //     public
  //     view
  //     returns (
  //         bytes32[] memory,
  //         uint256[] memory
  //     )
  // {
  //     uint256 assetCount = supportedAssets.length;

  //     bytes32[] memory assets = new bytes32[](assetCount);
  //     uint256[] memory periods = new uint256[](assetCount);

  //     IExchanger exchanger = IExchanger(addressResolver.getAddress(_EXCHANGER_KEY));

  //     for (uint256 i = 0; i < assetCount; i++) {
  //         bytes32 asset = supportedAssets[i];
  //         assets[i] = asset;
  //         periods[i] = exchanger.maxSecsLeftInWaitingPeriod(address(this), asset);
  //     }

  //     return (assets, periods);
  // }

  // MANAGER FEES

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
      currentTokenPrice
        .sub(_lastFeeMintPrice)
        .mul(_tokenSupply)
        .mul(_feeNumerator)
        .div(_feeDenominator)
      // Deprecated
      // .div(10**18);
        .div(currentTokenPrice);

    return available;
  }

  function mintManagerFee() public whenNotPaused {
    // Deprecated
    // _mintManagerFee(true);
    _mintManagerFee();
  }

  // Deprecated
  // function _mintManagerFee(bool settle) internal
  function _mintManagerFee() internal returns (uint256 fundValue) {
    // Deprecated
    //we need to settle all the assets before minting the manager fee
    // if (settle)
    //     _settleAll();

    uint256 fundValue = totalFundValue();
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

  // Deprecated
  // function getExitFee() external view returns (uint256, uint256) {
  //     return IHasFeeInfo(factory).getExitFee();
  // }

  function getExitCooldown() public view returns (uint256) {
    return IHasFeeInfo(factory).getExitCooldown();
  }

  function getExitRemainingCooldown(address sender) public view returns (uint256) {
    uint256 cooldown = getExitCooldown();
    uint256 cooldownFinished = lastDeposit[sender].add(cooldown);

    if (cooldownFinished < block.timestamp) return 0;

    return cooldownFinished.sub(block.timestamp);
  }

  // Swap contract

  // function setLastDeposit(address investor) public onlyDhptSwap {
  //     lastDeposit[investor] = block.timestamp;
  // }`

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
