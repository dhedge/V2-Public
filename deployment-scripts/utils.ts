export const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export const retryWithDelay = async <T>(
  fn: () => Promise<T>,
  functionType = "Function",
  retries = 30,
  interval = 10000,
  finalErr = Error("Retry failed"),
): Promise<T> => {
  try {
    return await fn();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } catch (err: any) {
    console.log(`${functionType} call failed: ${err.message}`);
    if (retries <= 0) {
      return Promise.reject(finalErr);
    }
    await wait(interval);
    return retryWithDelay(fn, functionType, retries - 1, interval, finalErr);
  }
};
