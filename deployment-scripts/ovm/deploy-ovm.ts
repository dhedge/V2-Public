import { getDeploymentData } from "../upgrade/getDeploymentData";
import { deploy } from "../deploy";

deploy(getDeploymentData(10, "production"));
