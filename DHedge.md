**Variables (14):**
- bytes32 private _EXCHANGE_RATES_KEY
- bytes32 private _SYNTHETIX_KEY
- bytes32 private _EXCHANGER_KEY
- bytes32 private _SYSTEM_STATUS_KEY
- bytes32 private _SUSD_KEY
- bool public privatePool
- address public creator
- uint256 public creationTime
- address public factory
- bytes32[] public supportedAssets
- mapping(bytes32 => uint256) public assetPosition
- mapping(bytes32 => bool) public persistentAsset
- uint256 public tokenPriceAtLastFeeMint
- mapping(address => uint256) public lastDeposit

**Events (8):**
- Deposit
- Withdrawal
- Exchange
- AssetAdded
- AssetRemoved
- PoolPrivacyUpdated
- ManagerFeeMinted
- ManagerFeeSet

**Interfaces (10):**
- "./ISynthetix.sol";
- "./IExchanger.sol";
- "./ISynth.sol";
- "./IExchangeRates.sol";
- "./IAddressResolver.sol";
- "./ISystemStatus.sol";
- "./Managed.sol";
- "./IHasDaoInfo.sol";
- "./IHasFeeInfo.sol";
- "./IHasAssetInfo.sol";

**Modifiers:**
- onlyPrivate

**functions (31):**
- initialize
- _beforeTokenTransfer - pool
- totalFundValue - pool
- deposit - pool
- withdraw - pool
- _withdraw - pool
- getFundSummary - pool
- tokenPrice - pool
- _tokenPrice - pool
- mintManagerFee - pool
- _mintManagerFee - pool
- getFundComposition - pool
- getExitFeeRemainingCooldown - pool
- getExitFeeCooldown - pool
- availableManagerFee - pool
- _availableManagerFee - pool
- setPoolPrivate - pool
- assetValue - pool

**Remove:**
- validateAsset - manager
- isAssetSupported - manager
- getSuspendedAssets - pool
- numberOfSupportedAssets - pool
- getAssetProxy - pool
- addToSupportedAssets - manager
- _addToSupportedAssets - manager
- removeFromSupportedAssets - manager
- exchange - manager
- getManagerFee - manager
- setManagerFeeNumerator - manager
