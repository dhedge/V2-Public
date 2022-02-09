import { getDeploymentData } from "../upgrade/getDeploymentData";
import { deploy } from "../deploy";

deploy(getDeploymentData(69, "staging"));
