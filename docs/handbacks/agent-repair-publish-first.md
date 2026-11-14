# Hand-back: W7 Publish first (`agent/repair-publish-first`), 2026-11-13

Brief: `docs/briefs/repair-lanes.md` W7. Decision: `docs/PRODUCT.md`, "Plan additions, 2026-11-13:
repair lanes", "Publish first". Stage: testing only. Nothing deployed.

## Phase 1: where a repair's time goes today

Sources: every runner log folder in `~/Library/Application Support/midas-runner/log` (57 jobs,
2026-10-16 to 11-13; step times from the files each step writes), plus the new shield steps timed
on this Mac on the real before/after files of the three requests below (the shield is not yet
called by `run-job.mjs`). Records: 12 To-Do records made with the copy's own tools.

### The three requests (all To-Do, live)

| Step | Colour: "make the text white" `92fb0f86` | Hide: "Remove the search feature from the bottom" `2da2e6b0` | Small feature: "add a plus button" `c3d1cdf8` | How it runs today |
|---|---|---|---|---|
| Pickup (report sent → runner claims) | 2.2 s | 15.6 s | 25.0 s | runner polls every 30 s |
| Setup (download report, fetch copy's tests, job folder, prompt) | 18.4 s | 12.5 s | 18.2 s | ~11 `wrangler r2 object get --remote`, one process each |
| Agent | 42.6 s | 44.3 s | 214.2 s | Claude Code, Opus |
| Tests compare + outcome | 0.8 s | 0.8 s | 0.8 s | |
| Deploy gate | 0.02 s | 0.00 s | 0.00 s | timed here |
| Shield: tools before/after | 0.04 s | 0.02 s | 0.02 s | timed here (not yet wired) |
| Shield: settings engine, records fit, primitive blocks | 0.01 s | 0.00 s | 0.00 s | timed here |
| Shield: page opens, first view + widget, old and new in parallel | 1.6 s | 1.0 s | 0.9 s | timed here |
| Shield: page opens, every view (12–14 taps), old then new | 20.0 s | 17.5 s | 15.2 s | timed here; how W1 runs it today |
| Copy's own tests (sandboxed vitest) | 0.5 s | 0.5 s | 0.4 s | runner log |
| Records fit (publish step's own) | 0.4 s | 0.2 s | 0.4 s | runner log |
| Upload + pointer + read back | 42.8 s | 16.7 s | 33.9 s | 13 puts + 2 gets + 1 D1 query + read-back get, one `wrangler --remote` process each, in a row |
| Summary, status, notices | 0.0 s | 0.0 s | 0.0 s | |
| Notice reaches the phone | avg 7.5 s | avg 7.5 s | avg 7.5 s | phone asks every 15 s (`RepairCenter.pollSeconds`) |
| **Total, report → live** | **107.7 s** | **90.5 s** | **292.9 s** | |
| Total once the shield is wired as W1 left it | ~129 s | ~109 s | ~309 s | adds the 15–20 s page taps before publish |

### All 31 published repairs

| Step | Median | Slowest tenth | Range |
|---|---|---|---|
| Pickup | 20.9 s | 30.0 s | 1.3–188.9 s |
| Setup | 20.6 s | 26.9 s | 10.6–29.4 s |
| Agent | 88.2 s | 277.5 s | 32.4–371.3 s |
| Gate + copy tests + records | 1.6 s | 2.2 s | |
| Upload + pointer + read back | 25.3 s | 39.1 s | 13.1–53.5 s |
| Total | 161.0 s | 355.0 s | 90.5–430.7 s |

One `wrangler` call costs about 0.9 s locally (`--local`, no network) and 1.5–3 s against
Cloudflare. Pickup, setup and upload are about 67 s of a median 161 s, all of it waiting or
starting `wrangler`; the checks that protect the person are under 3 s.
