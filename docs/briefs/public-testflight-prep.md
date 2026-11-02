# Public TestFlight, then the App Store (founder, 2026-10-23)

## Sequence to public TestFlight (lead, 2026-10-31; updated 2026-11-02; supersedes the tables below where they differ)

Build 22 (`docs/briefs/build-22-2026-10-31.md`, `docs/PRODUCT.md` "Plan additions, 2026-10-31" and
"2026-11-02") is the public build. Each stage needs the one before it. Drafts for every App Store
Connect field: `docs/briefs/app-store-submission.md`.

Ordering rule (founder, 2026-11-02): the founder tests build 22; deploys (staging, then live) come
last, right before App Store Connect.

Settled (founder, 2026-10-31): Make is in the public build. Tester cap is Apple's; not an item.
Contact and feedback email `bhuvanrj73@gmail.com`. The three-finger swipe (Edit) is described in
the review notes and What to Test (guideline 2.5.19). CONCERNS §20 and §21 are fixed in build 22
(`c720617`).

**0. Main checkout in sync (lead)**
- [ ] Local `main` is behind `origin/main`, with unpushed `fad17e8` (WIDGETS: every Sidekick ships
  a widget) and uncommitted edits (`CLAUDE.md`, `docs/PRODUCT.md`, `docs/PARALLEL-AGENTS.md`, this
  file, To-Do files). The PRODUCT.md sections and this section are now on `agent/docs-sync`.
  Commit or set the rest aside with their owner, then `git pull`.

**1. Code in build 22 (before the founder's test)**
- [x] Privacy manifest `shell/Midas/PrivacyInfo.xcprivacy` (UserDefaults, CA92.1); PRODUCT.md
  "Internal TestFlight readiness" corrected (2026-11-02).
- [x] Work log links (worktree `worklog-links`) merged (`5bb4016`).
- [x] Every account gets Reminders, Water and To-Do (`e81e6cd`, 2026-11-01), so a reviewer can try
  Edit on a fresh account.
- [x] Microphone purpose string: "Midas listens when you speak a request or an edit." (founder,
  2026-11-01; `8300bc7`).
- [x] Dead-end sweep (guideline 2.1), merged `8300bc7`. Leftover items 4-14: founder's call.
- [x] Onboarding with sign-in on the Midas popup (`ea73251`, `abbc6b2`).
- [ ] AI consent screen (5.1.2(i)): `agent/ai-consent`.
- [ ] Small fixes and the `scripts/test-all.sh` simulator: `agent/small-fixes`.
- [ ] To-Do widget: `agent/todo-widget`. To-Do typed-text fix: `agent/todo-add-fix`.
- [ ] Lost-passkey recovery by email: `agent/account-recovery`.
- [ ] Account deletion paths: `agent/account-deletion`.
- [ ] Privacy page words (founder, 2026-11-02) into `backend/src/public-pages.ts`: Edit "made by
  Anthropic's Claude coding assistant on a Midas server"; audio never leaves the phone; voice
  request log kept while the account exists, deleted with it; Cloudflare server logs (may include
  IP addresses, kept 7 days). Text in the submission draft §1.
- [ ] Everything merged into `main`, `scripts/test-all.sh` passes.

**2. Founder decisions on the drafts (the privacy page words ship with the server)**
- [x] Submission draft §6: 2 (fresh account has Sidekicks), 3 (name taken stays; review notes say
  type another name), 7 (voice log retention), 8 (Worker logs, IPs), 9 (mic text), settled
  2026-11-01/02.
- [ ] Still open: 1 (what "deleted within 7 days" covers: repair log, ops, runner logs, D1 Time
  Travel; paths being built), 4 (legal name), 5 (naming Cloudflare, OpenRouter, Anthropic), 6
  (Water as Health, push token as Device ID), 10 (age rating), 11 (marketing URL), 13 (4.7 / 4.7.2).

**3. Founder tests build 22 (Midas Test)**
- [ ] `cd ~/Desktop/Midas/midas/shell && xcodegen generate`; scheme **Midas Test**; on the
  founder's iPhone: onboarding, sign-up, jess, Make, Edit, Settings, delete a Sidekick, Delete
  Account, hint cloud, swipes, long press in the grid.

**4. Deploys, last, right before App Store Connect (`docs/DEPLOY.md`)**
- [ ] Staging: migrations 0011-0013, server, changed pages (Water, Reminders, To-Do,
  care-reminders, Boomi's copy), `assign-make-to-everyone`, `assign-starter-sidekicks-to-everyone`;
  open `/privacy` and `/support` on the staging URL.
- [ ] Live (founder): same order. Then `https://midas-api.midas-backend.workers.dev/privacy` is up.
- [ ] Runner on the Mac mini pulled and restarted; one live Edit job goes through.
- [ ] APNs key and secrets on staging and live; Cloudflare plan check and budget alert. Workers Logs
  move to Observability pricing on 2026-12-01 (Free 0.5 GB/day, 7 days, no overage; Paid 50
  GB/month included, then $0.25/GB ingested, $0.10/GB-month); Midas's volume is far below.

**5. Build upload and App Store Connect (founder)**
- [ ] Scheme **Midas**; archive; upload 0.1.0 (22) (or higher if 22 was already uploaded). Internal
  group installs it; end-to-end on live.
- [ ] Test Information (description, What to Test, feedback email, privacy policy URL), Beta App
  Review contact name and phone, review notes (sign-in, Edit swipe, 4.7 / 2.5.2 answer).
- [ ] External group with the build, submit to Beta App Review.
- [ ] After approval: public link on.

**6. Right after public TestFlight: the Midas landing page (founder, 2026-11-01, parked until then)**
- A plain landing page that explains what Midas is, every detail, and asks people to download it
  (TestFlight link). Nothing fancy.
- Look: not animated; drawn and painted, like https://www.heyaristotle.com. Inspiration:
  Michelangelo's The Creation of Adam, the touch between the two fingers. Follow `docs/DESIGN.md`.
- Earlier prototypes H1-H6 (`docs/mockups/home-page-2026-10-31.html`, merged from `agent/home-page`)
  are animated ink drawings: a starting point, not the brief. The agent's five open questions
  there (hand vs DESIGN.md §4, handwritten font on the site, complaint-first line, button label,
  jess in public copy) are still open.
- Privacy and support pages: P1 (plain), merged (`96a32e3`).

Earlier plan (2026-10-23), kept for history:

Founder, 2026-10-23: "lets tomorrow focus on public testflight and then next week focus on actual
app store launch." Prep only: nothing here is approved to build until the founder says so for each
item (CLAUDE.md, discuss then build). Governing date: VC application Nov 2.

## Plan

| When | Goal |
|---|---|
| Sat 2026-10-24 | Midas (live app) on external TestFlight with a public link |
| Week of 2026-10-26 | Midas on the App Store, unlisted (link only, no search) |

Testers on the public link install Apple's TestFlight app first; the link opens it and it keeps
Midas updated. Each build lasts 90 days.

## State (2026-10-23)

- Live runs main's server and pages (migrations 0001-0009, jess, router, queue, Workdesk), rolled
  out 2026-10-23. `JESS_GROW` on live: the founder's call (`npx wrangler secret put JESS_GROW`).
- Build number 10 (`7f0673e`), version 0.1.0; upload to "Midas" and "Midas Test" is the founder's.
- jess is assigned at sign-up (`backend/src/auth.ts`, founder 2026-10-22); nothing removes a
  Sidekick, so jess always stays. A new account gets jess only.
- The repair runner serves live and staging from the Mac mini; it has not yet run a live job.

## Public TestFlight: what is needed

| # | Item | Owner | State |
|---|---|---|---|
| 1 | Build 10 uploaded, internal testing first | founder | not uploaded |
| 2 | End-to-end test on live: Ask jess, queue, result card, Workdesk, repair by voice and circle, the runner's first live job | founder | after 1 |
| 3 | A new account is not empty or a dead end (guideline 2.1): what it starts with | founder decides | jess only today |
| 4 | Privacy policy URL (required for external testing) | founder; a session can draft | none in the repo |
| 5 | Test Information: beta description, What to Test, feedback email, contact | founder; a session can draft | not written |
| 6 | Review notes: sign-in is "Get Started", a name, Face ID; 4.7 and 2.5.2 answers (pages from the server in a closed web view, no other origins, no native code) | session drafts, founder approves | outline in `PRODUCT.md` §6 "Next steps" 0 |
| 7 | Dead-end sweep of the shell and both pages (no button to nowhere, no placeholder text) | session | not done |
| 8 | Build Sidekick (chat with the founder through jess and its tile, one inbox) | founder with a new agent | not started; decide whether it gates the public link |
| 9 | External group in App Store Connect with build 10, submit to Beta App Review, public link on after approval | founder | after 1-7 |
| 10 | Tester cap on the public link | founder decides | open |

Open since 2026-10-11, still unanswered: privacy policy URL and who drafts it; feedback and contact
email; public link tester limit; what this displaces before Nov 2.

## App Store (next week): added on top

1. Account deletion inside the app (guideline 5.1.1(v)): no route or screen exists today.
2. App Privacy details in App Store Connect (voice transcripts, records, repair report device info).
3. Support URL; screenshots for the required iPhone size; description, keywords, age rating,
   category.
4. No beta or placeholder wording anywhere (2.1, 2.2: betas belong on TestFlight).
5. Minimum functionality on day one (4.2).
6. EU: trader status under the Digital Services Act, or leave the EU out.
7. Unlisted distribution: request it from Apple; then normal App Review on every update (pages,
   repairs and jess changes come from the server and are not reviewed).

Main review risk on both paths: 2.5.2 (downloaded code that changes features; repairs and "jess
grows the Sidekick" do this) answered by 4.7 (HTML5 mini apps), whose rules include an index, a
report mechanism and 4.7.2 (no native APIs exposed to mini apps "without prior permission from
Apple"; midas-intel `docs/research/2026-10-22-shell-vs-native/`: request records fall under it on
its plain text, no public process found). Guideline text above is as known in June 2026; check
Apple's current pages before submitting.

Running in the background and not a gate unless the founder says so: runner uptime
(`docs/concerns/2026-10-13-repair-runner.md` §5), Cloudflare billing alert, "Jess" with a capital J,
light and dark icons.
