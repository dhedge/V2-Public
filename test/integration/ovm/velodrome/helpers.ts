import { BigNumber, BigNumberish } from "ethers";
import { IVelodromeGauge, IVelodromeV2Gauge } from "../../../../types";

export const getGaugeDepositParams = (amount: BigNumberish, v2: boolean): [string, unknown[]] =>
  v2 ? ["deposit(uint256)", [amount]] : ["deposit", [amount, 0]];

export type IVeloGauge = IVelodromeGauge | IVelodromeV2Gauge;

const isV2Gauge = (b: IVeloGauge): b is IVelodromeV2Gauge => {
  return (b as IVelodromeV2Gauge).stakingToken !== undefined;
};

export const getEarnedAmount = async (
  gauge: IVeloGauge,
  poolAddress: string,
  rewardToken: string,
): Promise<BigNumber> => {
  let claimAmount: BigNumber;

  if (isV2Gauge(gauge)) {
    claimAmount = await gauge.earned(poolAddress);
  } else {
    claimAmount = await gauge.earned(rewardToken, poolAddress);
  }

  return claimAmount;
};
