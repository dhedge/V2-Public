import { ethers } from "hardhat";
import { BigNumber, Contract, ContractReceipt, ContractTransaction } from "ethers";
import axios from "axios";
import { utils } from "../../utils/utils";
import { IBackboneDeploymentsParams } from "../../utils/deployContracts/deployBackboneContracts";
import { getMarketInfo, MarketInfo } from "./utils";
import { EventEmitterAbi } from "./EventEmitterAbi";
import { VirtualTokenOracleSettingStruct } from "../../../../types/IGmxExchangeRouterContractGuard";

export const GMX_ORACLE_LOOKUP_TYPE_PYTH_LIB = 2;

export type TokenPriceConfig = {
  oracleContractAddressOnchain: string;
  maxAgeOnchain: number;
  priceId: string;
  maxAgeOffchain: number;
  minConfidenceRatio: number;
};

export type GmxTestTokenAssetInfo = {
  amount: BigNumber;
  address: string;
  priceFeed: string;
  balanceOfSlot: number;
  priceConfig: TokenPriceConfig;
};

export type IGmxTestsParams = IBackboneDeploymentsParams & {
  multiplerToImpactForClaimCollateralTest: number;
  vaultCollateralAsset: string;
  vaultWithdrawalAsset: string;
  longCollateral: GmxTestTokenAssetInfo;
  shortCollateral: GmxTestTokenAssetInfo;
  gasToken: GmxTestTokenAssetInfo;
  market: string;
  exchangeRouter: string;
  approvalRouter: string;
  dataStore: string;
  reader: string;
  chainlinkDataStreamProviderArray: string[];
  referralStorage: string;
  pythOracleContract: string;
  uiFeeReceiver: string;
  orderVault: string;
  depositVault: string;
  withdrawalVault: string;
  orderHandler: string;
  depositHandler: string;
  withdrawalHandler: string;
  keeper: string;
  apiUrl: string;
  sizeAmount: BigNumber;
  underlyingTokensToAdd: (TokenPriceConfig & { address: string })[];
  vitrualTokenOracleSettings?: VirtualTokenOracleSettingStruct[];
};

export type GmxOrderParams = {
  uiFeeReceiver?: string;
  orderVault?: string;
  receiver?: string;
  collateralToken?: string;
  callbackContract?: string;
  onlySendTokens?: boolean;
  decreasePosition?: boolean;
  sizeDeltaUsd?: BigNumber;
  initialCollateralDeltaAmount?: BigNumber;
};
export type OrderType = "ORDER" | "DEPOSIT" | "WITHDRAWAL";

export const selectOppositeCollateralToken = ({ testParams }: { testParams: IGmxTestsParams }) => {
  const oppositeCollateral = [testParams.longCollateral, testParams.shortCollateral].find(
    (asset) => asset.address !== testParams.vaultCollateralAsset,
  );
  if (!oppositeCollateral) {
    throw new Error("Opposite collateral not found");
  }
  return oppositeCollateral;
};

export const selectTestTokenByAddress = ({
  assets,
  assetAddress,
}: {
  assets: GmxTestTokenAssetInfo[];
  assetAddress: string;
}) => {
  const testToken = assets.find((asset) => asset.address === assetAddress);
  if (!testToken) {
    throw new Error("Collateral not found");
  }
  return testToken;
};

export function deduplicateTestTokenByAddress(collaterals: GmxTestTokenAssetInfo[]): GmxTestTokenAssetInfo[] {
  const seenAddresses = new Set<string>();
  return collaterals.filter((collateral) => {
    if (seenAddresses.has(collateral.address)) {
      return false;
    }
    seenAddresses.add(collateral.address);
    return true;
  });
}

export function hashData(dataTypes, dataValues) {
  const bytes = ethers.utils.defaultAbiCoder.encode(dataTypes, dataValues);
  const hash = ethers.utils.keccak256(ethers.utils.arrayify(bytes));

  return hash;
}

export function hashString(string) {
  return hashData(["string"], [string]);
}

function accountListKey(account, type: OrderType) {
  return hashData(["bytes32", "address"], [hashString(`ACCOUNT_${type}_LIST`), account]);
}

function getAccountCount(dataStore: Contract, account: string, type: OrderType): Promise<number> {
  return dataStore.getBytes32Count(accountListKey(account, type));
}

function getAccountKeys(
  dataStore: Contract,
  account: string,
  type: OrderType,
  start: number,
  end: number,
): Promise<string[]> {
  return dataStore.getBytes32ValuesAt(accountListKey(account, type), start, end);
}

async function getLastAccountKey(dataStore: Contract, account: string, type: OrderType): Promise<null | string> {
  const orderCount = await getAccountCount(dataStore, account, type);
  if (orderCount === 0) {
    return null;
  }
  const orderKeys = await getAccountKeys(dataStore, account, type, orderCount - 1, orderCount);
  return orderKeys[0];
}

type SignedPricesType = {
  blob: string;
  tokenSymbol: string;
  tokenAddress: string;
  minBlockTimestamp: number;
  maxBlockTimestamp: number;
  maxPriceFull: string;
  minPriceFull: string;
}[];

const getOracleData = async ({ tokenAddr, apiUrl }: { tokenAddr: string; apiUrl: string }) => {
  const data = await axios.get(apiUrl);
  const dataItem = (data.data.signedPrices as SignedPricesType).filter(
    ({ tokenAddress }) => tokenAddress.toLowerCase() === tokenAddr.toLowerCase(),
  )[0];
  const { blob, maxBlockTimestamp } = dataItem;
  return { blob, maxBlockTimestamp };
};

export async function executeOrder({
  tokens,
  account,
  testParams,
  type,
}: {
  tokens: [string, string];
  account: string;
  testParams: IGmxTestsParams;
  type: OrderType;
}) {
  const keeperSigner = await utils.impersonateAccount(testParams.keeper);
  const dataStore = await ethers.getContractAt("IGmxDataStore", testParams.dataStore);

  const orderKey = await getLastAccountKey(dataStore, account, type);
  if (orderKey === null) {
    console.error("No order found");
    return;
  }
  let mTokens;

  try {
    const marketTokens: MarketInfo = await getMarketInfo(testParams);
    mTokens = [...new Set([marketTokens.indexToken, marketTokens.shortToken, marketTokens.longToken])];
  } catch {
    mTokens = tokens;
  }

  await utils.waitForRealTime();
  const data = await Promise.all(
    mTokens.map((token) => getOracleData({ tokenAddr: token, apiUrl: testParams.apiUrl })),
  );
  const oracleData = data.map((d) => d.blob);
  const timestamp = data.map(({ maxBlockTimestamp }) => maxBlockTimestamp).reduce((a, b) => Math.max(a, b), 0);

  // may fail if the timestamp is not the same as that in the api
  await ethers.provider.send("evm_setNextBlockTimestamp", [timestamp]);
  // Mine the block with the set timestamp
  await ethers.provider.send("evm_mine", []);

  const tokensParams: string[] = mTokens;
  const providersParams = new Array(mTokens.length).fill(testParams.chainlinkDataStreamProviderArray[0]);
  const oracleDataParams = oracleData;
  // weird that different token has a different chainlinkDataStreamprovider
  try {
    const params = {
      tokens: tokensParams,
      providers: providersParams,
      data: oracleDataParams,
    };

    let tx: ContractTransaction;
    switch (type) {
      case "ORDER": {
        const orderHandler = await ethers.getContractAt("IGmxOrderHandler", testParams.orderHandler);
        tx = await orderHandler.connect(keeperSigner).executeOrder(orderKey, params, { gasLimit: 30000000 });
        break;
      }
      case "DEPOSIT": {
        const depositHandler = await ethers.getContractAt("IGmxDepositHandler", testParams.depositHandler);
        tx = await depositHandler.connect(keeperSigner).executeDeposit(orderKey, params, { gasLimit: 20000000 });
        break;
      }
      case "WITHDRAWAL": {
        const withdrawalHandler = await ethers.getContractAt("IGmxWithdrawalHandler", testParams.withdrawalHandler);
        tx = await withdrawalHandler.connect(keeperSigner).executeWithdrawal(orderKey, params, { gasLimit: 20000000 });
        break;
      }
    }
    const rptx = await tx.wait(1);
    // get reasonBytes from it to see what is wrong
    await getEventFromReceipt(rptx);
    return tx.hash;
  } catch (e) {
    // got InvalidOracleProviderForToken error; try with another one
    console.log("executeOrder error", e);
  }
}

async function getEventFromReceipt(receipt: ContractReceipt) {
  // Loop through logs in the transaction receipt
  for (const event of receipt.events || []) {
    try {
      const iface = new ethers.utils.Interface(EventEmitterAbi);
      // Decode log based on your event signature
      const parsedLog = iface.parseLog(event);

      // Check if the eventName is "OrderCancelled"
      if (parsedLog.name === "EventLog2" && !!parsedLog.args[1] && parsedLog.args[1] === "OrderCancelled") {
        // only print when there is a cancelled order from executeOrder, executeDeposit, executeWithdrawal
        console.log("event:", event);
        console.log("Found OrderCancelled event args:", JSON.stringify(parsedLog.args, null, 2));
      }
    } catch (error) {
      // If the log isn't a known event, ignore it
      continue;
    }
  }
}
