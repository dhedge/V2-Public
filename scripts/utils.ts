export const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export const retryWithDelay = async (
  fn: any,
  functionType = "Function",
  retries = 30,
  interval = 10000,
  finalErr = Error("Retry failed"),
): Promise<void> => {
  try {
    await fn();
  } catch (err) {
    console.log(`${functionType} call failed: ${err.message}`);
    if (retries <= 0) {
      return Promise.reject(finalErr);
    }
    await wait(interval);
    return retryWithDelay(fn, functionType, retries - 1, interval, finalErr);
  }
};
