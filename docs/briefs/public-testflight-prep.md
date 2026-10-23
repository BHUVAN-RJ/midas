# Public TestFlight, then the App Store (founder, 2026-10-23)

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
