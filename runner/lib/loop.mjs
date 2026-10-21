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

// One claim across every environment the runner serves (founder, 2026-10-21: one runner, live
// and staging, one job at a time). Each call asks the environments in turn, starting after the
// one that gave the last job, so a busy environment cannot keep the other waiting. Resolves with
// { job, backend } (the job carries backend.environment) or null when none has a job. A failing
// environment is reported to onError and the others are still asked.
export function claimFromEnvironments({ backends, onError = () => {} }) {
  let nextIndex = 0;
  return async function claimNextJob() {
    for (let offset = 0; offset < backends.length; offset += 1) {
      const index = (nextIndex + offset) % backends.length;
      const backend = backends[index];
      let job = null;
      try {
        job = await backend.claimJob();
      } catch (error) {
        onError(new Error(`${backend.environment}: ${error.message}`));
        continue;
      }
      if (job !== null) {
        nextIndex = (index + 1) % backends.length;
        return { job, backend };
      }
    }
    return null;
  };
}
