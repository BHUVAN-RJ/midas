// The runner loop: claim one job, run it to the end, claim the next. One job at a time; when
// there is none, run `whenIdle` (the re-runs of edits the founder made by hand, founder 2026-11-02)
// and wait. With `waitForWork` (publish first, W7 2026-11-13) the wait is a long poll that ends the
// moment a job can be claimed; when it fails the loop waits pollIntervalMs as before. Stops when
// `shouldStop()` returns true.
export async function runLoop({ claimJob, runJob, pollIntervalMs, sleep, shouldStop = () => false, onError = () => {}, whenIdle = async () => {}, waitForWork = null }) {
  while (!shouldStop()) {
    let job = null;
    try {
      job = await claimJob();
    } catch (error) {
      onError(error);
    }
    if (job === null) {
      try {
        await whenIdle();
      } catch (error) {
        onError(error);
      }
      await waitBeforeNextClaim({ waitForWork, sleep, pollIntervalMs, onError });
      continue;
    }
    try {
      await runJob(job);
    } catch (error) {
      onError(error);
    }
  }
}

async function waitBeforeNextClaim({ waitForWork, sleep, pollIntervalMs, onError }) {
  if (waitForWork === null) {
    await sleep(pollIntervalMs);
    return;
  }
  try {
    await waitForWork();
  } catch (error) {
    onError(error);
    await sleep(pollIntervalMs);
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

// The long poll across every environment the runner serves (W7): each environment's Worker is
// asked at once (backend.waitForJob); resolves true the moment any has a job, false when every
// wait ran out. An environment whose wait fails (an older Worker without the route) is reported
// and counts as "no job yet"; when every one fails it throws, and the loop falls back to its poll.
export function waitFromEnvironments({ backends, seconds, onError = () => {} }) {
  return function waitForAnyEnvironment() {
    return new Promise(function settleWhenAnyIsReady(resolve, reject) {
      let pending = backends.length;
      let failures = 0;
      let settled = false;
      function finishOne() {
        pending -= 1;
        if (pending > 0 || settled) {
          return;
        }
        settled = true;
        if (failures === backends.length) {
          reject(new Error("no environment answered the long poll"));
          return;
        }
        resolve(false);
      }
      function onReady(ready) {
        if (ready === true && !settled) {
          settled = true;
          resolve(true);
          return;
        }
        finishOne();
      }
      function onWaitFailed(environmentName, error) {
        failures += 1;
        onError(new Error(`${environmentName}: ${error.message}`));
        finishOne();
      }
      if (backends.length === 0) {
        resolve(false);
        return;
      }
      for (const backend of backends) {
        const waited = Promise.resolve().then(function askThisEnvironment() {
          return backend.waitForJob(seconds);
        });
        waited.then(onReady, function reportWaitFailure(error) {
          onWaitFailed(backend.environment, error);
        });
      }
    });
  };
}
