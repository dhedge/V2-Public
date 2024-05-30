import { IVelodromeCLTestParams } from "./velodromeCLTestDeploymentHelpers";
import { clGaugeContractGuardCommonTest } from "./CLGaugeContractGuardCommonTest";
import { clGaugeContractGuardVelodromeSpecificTest } from "./CLGaugeContractGuardVelodromeSpecificTest";

export const velodromeCLGaugeContractGuardTest = (testParams: IVelodromeCLTestParams) => {
  clGaugeContractGuardCommonTest(testParams);
  clGaugeContractGuardVelodromeSpecificTest(testParams);
};
