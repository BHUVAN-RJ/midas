# Concerns: edit could not be made, /privacy and /support (build 22, 2026-10-31)

Branch `agent/edit-failed-store`, commit `8628e71`, merged into `main` as `36caec1`. Contract:
`docs/briefs/edit-failed-contract.md`. App Store drafts: `docs/briefs/app-store-submission.md`.

## Open

- **Make sender name "Make" not done on the server.** test-guardian refused to change the asserts
  pinning "Bhuvan" (`backend/test/make-routes.test.ts:299`, `backend/test/make-sync.test.ts:483`,
  `:486`): the decision is only in the untracked build-22 brief, not in `docs/PRODUCT.md`. Refusal
  logged in `TEST_CHANGES.md`. Who: lead adds the dated decision to `docs/PRODUCT.md`, sets
  `MAKE_SENDER_NAME = "Make"` in `backend/src/make-sidekick.ts`, resends the request to
  test-guardian. The shell's `MakeCopy.senderName` is edit-voice's.
- **`scripts/test-all.sh` shell step fails:** its default simulator "iPhone 17" no longer exists, and
  the guard hook blocks `scripts/sim.sh run scripts/test-all.sh`. This branch's shell suite was run
  by hand on leased "Midas Sim 2" (1028 tests, 0 failures). Who: founder (guard files) or lead.
- **Deploy needed** for `/privacy` and `/support` to be live at
  `https://midas-api.midas-backend.workers.dev/privacy` and `/support` (server only, no migration).
  Who: founder, `docs/DEPLOY.md`, before App Store Connect gets the URLs.
- **Job link is a path on the Mac mini** (`~/Library/Application Support/midas-runner/log/<report id>`),
  not a web link. Nothing serves job pages.
- **jess request waiting on a failed edit stays Not Done** after the founder fixes it by hand
  (jess-pending is not re-run).
- **Shell must handle a later `fixed` notice** for a report it showed as Couldn't Fix (move card Not
  Done → Done). Contract section 1. Who: edit-voice.
- **Runner flake:** two runner tests timed out once in a full backend run under load; passed alone.
- **App Store answers for the founder** (`docs/briefs/app-store-submission.md` section 6):
  - "Deleted within 7 days" vs data never trimmed: repair log, synced records, backups, job logs on
    the Mac.
  - Reviewer cannot try Edit on a new account (only jess and Make until everyday Sidekicks are
    assigned at sign-up), or give a demo account.
  - Name uniqueness for reviewer accounts.
  - Naming Cloudflare, OpenRouter, Anthropic on the privacy page vs the public word list.
  - Water as Health data, push token as Device ID, time zone as location.
  - Retention periods; Worker logs hold IP addresses.
  - `NSMicrophoneUsageDescription` text is vague.
  - Age rating, marketing URL, founder name and phone for contact fields, founder name on the
    privacy page (left off).
  - Check current Apple text of 2.5.2, 4.7, 4.7.2 before submitting.

## Done

- 2026-10-31: could-not-edit path (person sees "Check back in some time.", founder inbox thread and
  push, Built closes it), `/privacy`, `/support`, App Store drafts. Tests:
  `backend/test/edit-failed-store.test.ts` (15), `backend/test/public-pages.test.ts` (6). Backend
  1205/1205, guard 42, midas-intel 31, shell 1028/0.
