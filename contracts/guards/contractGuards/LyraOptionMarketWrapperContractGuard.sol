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
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../utils/TxDataUtils.sol";
import "../../utils/tracker/DhedgeNftTrackerStorage.sol";
import "../../interfaces/guards/ITxTrackingGuard.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/lyra/IOptionMarket.sol";
import "../../interfaces/lyra/IOptionMarketViewer.sol";
import "../../interfaces/lyra/IOptionMarketWrapper.sol";
import "../../interfaces/lyra/IShortCollateral.sol";
import "../../interfaces/lyra/ILyraRegistry.sol";
import "../../interfaces/synthetix/IAddressResolver.sol";

/// @title Transaction guard for Lyra OptionMarketWrapper
contract LyraOptionMarketWrapperContractGuard is TxDataUtils, ITxTrackingGuard {
  using SafeMathUpgradeable for uint256;

  bytes32 public constant NFT_TYPE = keccak256("LYRA_NFT_TYPE");
  address public immutable nftTracker;
  uint256 public immutable maxPositionCount;

  bytes32 public constant MARKET_VIEWER = "MARKET_VIEWER";
  bytes32 public constant MARKET_WRAPPER = "MARKET_WRAPPER";
  bytes32 public constant SYNTHETIX_ADAPTER = "SYNTHETIX_ADAPTER";

  struct OptionPosition {
    address optionMarket;
    uint256 positionId;
  }

  bool public override isTxTrackingGuard = true;
  ILyraRegistry public immutable lyraRegistry;

  constructor(ILyraRegistry _lyraRegistry, address _nftTracker, uint256 _maxPositionCount) {
    lyraRegistry = _lyraRegistry;
    nftTracker = _nftTracker;
    maxPositionCount = _maxPositionCount;
  }

  function marketViewer() public view returns (IOptionMarketViewer) {
    return IOptionMarketViewer(lyraRegistry.getGlobalAddress(MARKET_VIEWER));
  }

  function marketWrapper() public view returns (address) {
    return lyraRegistry.getGlobalAddress(MARKET_WRAPPER);
  }

  function getOptionPositions(address poolLogic) public view returns (OptionPosition[] memory optionPositions) {
    bytes[] memory data = DhedgeNftTrackerStorage(nftTracker).getAllData(NFT_TYPE, poolLogic);
    optionPositions = new OptionPosition[](data.length);
    for (uint256 i = 0; i < data.length; i++) {
      optionPositions[i] = abi.decode(data[i], (OptionPosition));
    }
  }

  /// @notice Transaction guard for OptionMarketWrapper - used for Toros
  /// @dev It supports close/open/forceClose position
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    public
    virtual
    override
    returns (
      uint16 txType,
      bool // isPublic
    )
  {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    require(poolManagerLogicAssets.isSupportedAsset(to), "lyra not enabled");

    settleExpiredAndFilterActivePositions(IPoolManagerLogic(_poolManagerLogic).poolLogic());

    bytes4 method = getMethod(data);
    if (method == IOptionMarketWrapper.openPosition.selector) {
      IOptionMarketWrapper.OptionPositionParams memory params = abi.decode(
        getParams(data),
        (IOptionMarketWrapper.OptionPositionParams)
      );

      _checkSupportedAsset(poolManagerLogicAssets, params.optionType, address(params.optionMarket));
      txType = 26;

      settleExpiredAndFilterActivePositions(IPoolManagerLogic(_poolManagerLogic).poolLogic());
    } else if (method == IOptionMarketWrapper.closePosition.selector) {
      IOptionMarketWrapper.OptionPositionParams memory params = abi.decode(
        getParams(data),
        (IOptionMarketWrapper.OptionPositionParams)
      );

      _checkSupportedAsset(poolManagerLogicAssets, params.optionType, address(params.optionMarket));
      txType = 27;

      settleExpiredAndFilterActivePositions(IPoolManagerLogic(_poolManagerLogic).poolLogic());
    } else if (method == IOptionMarketWrapper.forceClosePosition.selector) {
      IOptionMarketWrapper.OptionPositionParams memory params = abi.decode(
        getParams(data),
        (IOptionMarketWrapper.OptionPositionParams)
      );

      _checkSupportedAsset(poolManagerLogicAssets, params.optionType, address(params.optionMarket));
      txType = 28;

      settleExpiredAndFilterActivePositions(IPoolManagerLogic(_poolManagerLogic).poolLogic());
    }

    return (txType, false);
  }

  function _checkSupportedAsset(
    IHasSupportedAsset poolManagerLogic,
    IOptionMarket.OptionType optionType,
    address optionMarket
  ) internal view {
    IOptionMarketViewer.OptionMarketAddresses memory optionMarketAddresses = marketViewer().marketAddresses(
      optionMarket
    );

    // if short-call-base option type, check base asset
    if (optionType == IOptionMarket.OptionType.SHORT_CALL_BASE) {
      require(poolManagerLogic.isSupportedAsset(address(optionMarketAddresses.baseAsset)), "unsupported base asset");
    } else {
      // otherwise, check quote asset
      require(poolManagerLogic.isSupportedAsset(address(optionMarketAddresses.quoteAsset)), "unsupported quote asset");
    }
  }

  /// @notice This function is called after execution transaction (used to track transactions)
  /// @dev It supports close/open/forceClose position
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  function afterTxGuard(address _poolManagerLogic, address to, bytes calldata data) public virtual override {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic, "not pool logic");

    IOptionMarketWrapper.OptionPositionParams memory params = abi.decode(
      getParams(data),
      (IOptionMarketWrapper.OptionPositionParams)
    );
    afterTxGuardHandle(to, poolLogic, address(params.optionMarket), params.positionId);
  }

  function afterTxGuardHandle(
    address contractGuarded,
    address poolLogic,
    address optionMarket,
    uint256 positionId
  ) internal {
    IOptionMarketViewer.OptionMarketAddresses memory optionMarketAddresses = marketViewer().marketAddresses(
      optionMarket
    );
    // If the manager is not specifying a positionId it means he must be creating a new position
    // We use the optionMakets "nextId" to determine the last Id created and store that for the pool
    // "nextId" starts from 1 so the positionId starts from 1.
    if (positionId == 0) {
      // New position created, We use the nextId sub 1 as this code runs after the creation of the option.
      DhedgeNftTrackerStorage(nftTracker).addData(
        contractGuarded,
        NFT_TYPE,
        poolLogic,
        abi.encode(
          OptionPosition({
            optionMarket: optionMarket,
            positionId: IOptionToken(optionMarketAddresses.optionToken).nextId().sub(1)
          })
        )
      );

      require(
        DhedgeNftTrackerStorage(nftTracker).getDataCount(NFT_TYPE, poolLogic) <= maxPositionCount,
        "exceed maximum position count"
      );

      // If the manager is specifying a positionId it must mean he is trying to make changes to an existing one
      // We detect if it is closed and remove it from storage
    } else {
      IOptionToken.PositionState positionState = IOptionToken(optionMarketAddresses.optionToken).getPositionState(
        positionId
      );

      // find option position from nft tracker
      OptionPosition[] memory optionPositions = getOptionPositions(poolLogic);
      uint256 i;
      for (i = 0; i < optionPositions.length; i++) {
        if (optionPositions[i].optionMarket == optionMarket && optionPositions[i].positionId == positionId) {
          break;
        }
      }

      require(i < optionPositions.length, "position is not in track");

      if (positionState != IOptionToken.PositionState.ACTIVE) {
        // If the position is not active remove it from nft tracker
        DhedgeNftTrackerStorage(nftTracker).removeData(contractGuarded, NFT_TYPE, poolLogic, i);
      }
    }
  }

  function removeClosedPosition(address poolLogic, address optionMarket, uint256 positionId) external {
    OptionPosition[] memory optionPositions = getOptionPositions(poolLogic);
    // We need to find which array index is the position we want to delete
    for (uint256 i = 0; i < optionPositions.length; i++) {
      if (optionPositions[i].optionMarket == optionMarket && optionPositions[i].positionId == positionId) {
        IOptionMarketViewer.OptionMarketAddresses memory optionMarketAddresses = marketViewer().marketAddresses(
          optionMarket
        );

        // Once we find it we check to make sure the postion is not active
        require(
          IOptionToken(optionMarketAddresses.optionToken).getPositionState(positionId) !=
            IOptionToken.PositionState.ACTIVE,
          "not closed position"
        );

        DhedgeNftTrackerStorage(nftTracker).removeData(marketWrapper(), NFT_TYPE, poolLogic, i);
        break;
      }
    }
  }

  /// @notice Function for settling expired options and filtering active options
  /// @dev Used when interacting with the OptionMarketWrapper contract
  function settleExpiredAndFilterActivePositions(address poolLogic) public {
    _settleExpiredAndFilterActivePositions(poolLogic, marketWrapper());
  }

  /// @notice Public function for settling expired options and filtering active options
  /// @dev Includes a guardecContract input for handling calls directly through the OptionMarket contract (not wrapper)
  function settleExpiredAndFilterActivePositions(address poolLogic, address guardedContract) public {
    _settleExpiredAndFilterActivePositions(poolLogic, guardedContract);
  }

  function _settleExpiredAndFilterActivePositions(address poolLogic, address guardedContract) internal {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(IPoolLogic(poolLogic).poolManagerLogic());

    OptionPosition[] memory optionPositions = getOptionPositions(poolLogic);

    // 1. we filter active option positions
    // 2. we settle expired option positions
    // 3. we removed expired/inactive option positions from nft tracker
    for (uint256 i = optionPositions.length; i > 0; i--) {
      uint256 index = i - 1;
      IOptionMarketViewer.OptionMarketAddresses memory optionMarketAddresses = marketViewer().marketAddresses(
        optionPositions[index].optionMarket
      );
      IOptionToken.OptionPosition memory position = IOptionToken(optionMarketAddresses.optionToken).positions(
        optionPositions[index].positionId
      );
      if (position.state == IOptionToken.PositionState.ACTIVE) {
        (, uint256 priceAtExpiry, ) = IOptionMarket(optionPositions[index].optionMarket).getSettlementParameters(
          position.strikeId
        );

        if (priceAtExpiry == 0) {
          continue;
        }

        // settlement will return base or quote asset back to the pool
        // we check if quote/base asset is supported for option position type
        _checkSupportedAsset(poolManagerLogicAssets, position.optionType, optionPositions[index].optionMarket);

        uint256[] memory positionsToSettle = new uint256[](1);
        positionsToSettle[0] = optionPositions[index].positionId;
        IShortCollateral(optionMarketAddresses.shortCollateral).settleOptions(positionsToSettle);
      }

      DhedgeNftTrackerStorage(nftTracker).removeData(guardedContract, NFT_TYPE, poolLogic, index);
    }
  }
}
