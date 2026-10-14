// The runner loop: claim one job, run it to the end, claim the next. One job at a time; when
// there is none, wait pollIntervalMs. Stops when `shouldStop()` returns true.
export async function runLoop({ claimJob, runJob, pollIntervalMs, sleep, shouldStop = () => false, onError = () => {} }) {
  while (!shouldStop()) {
    let job = null;
    try {
      job = await claimJob();
    } catch (error) {
      onError(error);
    }
    if (job === null) {
      await sleep(pollIntervalMs);
      continue;
    }
    try {
      await runJob(job);
    } catch (error) {
      onError(error);
    }
  }
}

export function sleepMs(milliseconds) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}
