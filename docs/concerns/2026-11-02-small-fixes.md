# Concerns: build 22 small fixes (2026-11-02)

Branch `agent/small-fixes`, commits `eabf61a` (deleted Workdesk card stays deleted; test-all.sh
leases a pool simulator) and `72d1422` (jess request follows the founder's hand-fixed edit, pick B).
Not merged. Full suite passed on `72d1422`: guard 42, backend 1366/1366, shell 1168/0,
midas-intel 31.

## Open

- **Merge** `agent/small-fixes` into `main`. Who: lead.
- **Founder decision to record** (2026-11-02, in chat): a jess request whose edit failed and was
  fixed by hand is re-run on the fix; the card shows Taking a Deeper Look, then Done (pick B).
  Goes into `docs/PRODUCT.md` section 6 "Small fixes" and the midas-intel design doc. Who: lead
  (worktrees may not edit `docs/PRODUCT.md`).
- **Stale docs after merge.** Who: lead.
  - `docs/briefs/edit-failed-contract.md` section 4: drop the "stays Not Done after the founder's
    fix" limit.
  - `docs/PRODUCT.md` section 6: mark the three small fixes done; drop any note that test-all.sh
    needs a hand-run simulator.
- **Deploy order for fix 1.** Server first (staging, then live; no migration), then the runner on the
  Mac mini (`docs/DEPLOY.md` 3.4), then the next app build for the shell parts. A runner updated
  before live has `GET /repairs/jess-reruns` only logs errors for live. Who: founder.
- **Limits of fix 1.**
  - The runner re-runs hand-fixed requests only between jobs. If it does not do so within 10
    minutes of Built, `failFinished` fails the request ("live but not run again") and the card shows
    Not Done.
  - A hand-fixed copy without `tools.js` re-runs nothing; the request fails after 10 minutes.
- **Limit of fix 2.** A deleted card's request still runs on the server (the reminder is still
  added); only its card stays gone.
