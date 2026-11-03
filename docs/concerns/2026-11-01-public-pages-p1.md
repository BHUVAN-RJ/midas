# Concerns: /privacy and /support in the P1 look (2026-11-01)

Task: lead message, founder 2026-11-01: build P1 "Plain" (`docs/mockups/public-pages-2026-10-31.html`)
into `backend/src/public-pages.ts`. Branch `agent/home-page`, commit `96a32e3` (mockups `228101c`).
Not merged, not deployed.
Suites at hand-back: guard 42/42, backend 1260/1260 (new file `backend/test/public-pages-p1.test.ts`,
6 checks, 5 fail on the old page), midas-intel 31/31. Shell suite did not run, see below.

## Open

- **Shell suite not run.** `scripts/test-all.sh` looks for an "iPhone 17" simulator; only
  "Midas Sim 1" and "Midas Sim 2" exist, both booted by other sessions. xcodebuild: `Unable to find
  a device matching the provided destination specifier`. No shell code changed on this branch.
  Lead or test-guardian reruns with `MIDAS_SIMULATOR` set to a free Midas Sim before merging.
- **Wordmark is not a link.** No home page is served yet. When one is, link the header wordmark to
  `/` (one line in `renderPage`). Founder pick.
- **Home page prototypes H1–H6 parked** (founder, 2026-11-01). `docs/mockups/home-page-2026-10-31.html`
  stays as is; no pick made. Pick up when the founder reopens the home page.

## For the lead

- Merge `agent/home-page` after the shell suite passes, then deploy the server (`docs/DEPLOY.md`)
  so live /privacy and /support get the new look.
- `docs/PRODUCT.md`: record P1 chosen for /privacy and /support, home page parked (2026-11-01).
  Lead moves it.
