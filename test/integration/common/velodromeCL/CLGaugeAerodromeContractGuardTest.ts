import { IVelodromeCLTestParams } from "./velodromeCLTestDeploymentHelpers";
import { clGaugeContractGuardCommonTest } from "./CLGaugeContractGuardCommonTest";
import { clGaugeContractGuardAerodromeSpecificTest } from "./CLGaugeContractGuardAerodromeSpecificTest";

export const aerodromeCLGaugeContractGuardTest = (testParams: IVelodromeCLTestParams) => {
  clGaugeContractGuardCommonTest(testParams);
  clGaugeContractGuardAerodromeSpecificTest(testParams);
};
