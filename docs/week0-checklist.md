# Week 0 checklist

Source of truth for the gates: `docs/designs/jess-personal-assistant-shell.md`, section
`## v1 Re-plan, 2026-09-25: the Nov 2 Deadline`, subsection `### Calendar`, the W0 paragraph,
and section `## The Assignment`. Build 1 submits **Thu Oct 8**. Started 2026-09-30.

Mark an item `[x]` only when the artifact exists, not when it is understood.

> **References to the design doc are by section heading, not line number**, rewritten
> 2026-10-04, because line numbers go stale every time the doc is edited. "Design doc" below
> means `docs/designs/jess-personal-assistant-shell.md`. New in the design doc since this
> checklist was written: the Wabi competitor record, the guideline 2.5.2 risk in Accepted
> risks, Apple's mini app rules, and the device connector and widget direction.

---

## Pick up here (state at end of 2026-10-04)

Repo: `github.com/BHUVAN-RJ/midas`, private, branch `main`. The local folder is now
`~/Desktop/midas`. The repo holds docs and the backend skeleton in `backend/`.

Done on 2026-10-04: repo created and pushed, bundle ID registered (Push Notifications and Sign
in with Apple enabled), App Store Connect app record created, and the founder's architecture
calls recorded in the design doc under `## Architecture Decisions, 2026-10-04`. Read that
section first; it changes build 1.

Backend skeleton deployed 2026-10-05 from `backend/`: Worker `midas-api`, D1 database `midas`
bound as `DB`, R2 bucket `midas-bundles` bound as `BUNDLES`. `GET /health` probes both bindings
and returned 200 at `https://midas-api.midas-backend.workers.dev/health`. Redeploy with
`npx wrangler deploy` from `backend/`. The Worker holds no tables and no features yet.

Section 3 is complete: the founder opened the health URL on the phone on 2026-10-05.

**Next step: the Xcode project for the iPhone shell**, which needs the exact bundle ID string
(open question 1).

Waiting on the founder, in order of urgency:

1. Start the control run (section 4). The founder said on 2026-10-04 it starts 2026-10-05. It
   needs a full calendar week.
2. Wabi 2.0 invite (section 6): the founder reported on 2026-10-04 that Wabi does not let
   them log in, so the invite cannot be requested for now.
3. Collect Apple ID emails from the friends who will test, for internal TestFlight.

Decided 2026-10-04: the backend is hosted on Cloudflare (Workers, D1, R2), chosen as the
fastest to set up, with the choice open to change later. The founder also has an always-on Mac
mini at home, not used for hosting.

Decided 2026-10-04: Oct 8 means internal TestFlight only, using the 100 internal tester
slots. External TestFlight and Beta App Review are not this week's concern. The founder
collects friends' Apple ID emails once the app is built.

Open questions the founder has not answered yet:

1. The exact bundle ID string that was registered. `com.bhuvanrj.midas` was suggested. The
   Xcode project needs it.
2. Shed order for the new build 1 scope. Proposed: the birthdays Sidekick first, then the
   consent screen becomes a plain system alert, then metrics shrink to open events only.
3. Whether every friend gets all three Sidekicks or the founder assigns them per person, which
   needs one small assignments table.

---

## 0. Naming (blocks items 2 and 3)

The platform is being renamed off "jess". The repo name and the App Store Connect record both
need the final name, and the App Store Connect name must be unique across the store, so this
is the first gate.

- [x] Pick the platform name: **Midas**, decided 2026-10-04. The assistant stays jess, the
      mini apps stay Sidekicks.
- [x] Check App Store name availability in App Store Connect. Done 2026-10-04: "Midas" alone
      is already in use. The store listing name is "Midas: Apps for You". The founder's message
      left it unclear whether the registered string includes the word "Made" ("Midas: Apps
      Made for You"), so read the exact string off the App Store Connect record. The home
      screen display name stays Midas.
- [x] Domain and repo name: the founder has `heymidas.app` (stated 2026-10-04), and the repo
      is `BHUVAN-RJ/midas`.
- [x] The mini apps are called Sidekicks, confirmed by the founder 2026-10-04 (the doc said "sidekicks", and the design doc's `## Sidekicks: the Product Noun` section already
      flags that name as crowded: Perplexity sunset the Sidekick browser Aug 3 2025, plus
      getasidekick.ai, TrendSpider Sidekick, and two App Store entries)
- [ ] Note: the design doc's `### Down the line, not v1 and not v2: Siri exposure` section says the spoken Siri phrase uses the iOS app display name, so a rename now
      is free and a rename after the action layer ships is not

### Naming record, 2026-10-01 and 2026-10-02

Candidates discussed and dropped on Oct 1: Bob (live US mark #6264257, HiBob), Operator (two
live personal AI agents own it), Sidekick as a company name (see the design doc, `## Sidekicks: the Product Noun`), Juno, Hugo, Odin,
Goose, Q (each blocked by a live AI product of the same name). Cook was the best fit to the
verb rubric and is undecided.

Shortlist checked on Oct 2: **Midas** (founder's default, "if there's nothing, we'll go with
Midas") and **Edith**. Checks run: USPTO via Trademarkia, App Store, live products, DNS plus
RDAP for `{name, try, get, hey, ask, use, my}` across .com, .app, .ai, .io.

**Midas**
- Trademark: no live MIDAS mark for consumer software or AI. Midas International (auto repair)
  holds live MIDAS and THE MIDAS TOUCH registrations whose class 42 entries are muffler and
  brake shop services, not software. DEAL MIDAS (class 9, private equity CRM) and MIDAS by IMS
  Software (class 9, pharmaceutical data) are the nearest software marks, both narrow.
- Live product conflict: Midas, trymidas.ai, AI verification startup, 10M dollar round led by
  Nova Global, launched Feb 2026, enterprise. Same word, AI category, no consumer overlap. This
  is the one a trademark examiner or an investor would raise.
- Domains: midas.com, .app, .io registered and in use; midas.ai for sale on Afternic at 595,000
  dollars. try, get, use and my prefixes taken on .com, .app, .io. **Available: heymidas.app,
  heymidas.ai, heymidas.io, askmidas.app, askmidas.ai, askmidas.io, mymidas.ai.**

**Edith**
- Trademark: no live EDITH mark in class 9 or 42. Live marks are roses, tiles, wine, and
  pending cosmetics and entertainment.
- Live product conflict: Edith by Quillow (heyedith.com, launched Jan 2025), a proactive
  personal AI agent for reminders and tasks over WhatsApp, SMS, phone and iOS. Same consumer
  category and the same pitch, so direct confusion regardless of trademark state.
- Domains: edith.com, .app, .ai, .io all registered. **Available: tryedith.app, tryedith.io,
  getedith.ai, heyedith.app, heyedith.io, askedith.app, askedith.io, useedith.app, useedith.ai,
  useedith.io, myedith.app, myedith.ai, myedith.io.**

Not yet done: a USPTO search by a lawyer, App Store name check from a device, and a decision.
No domain has been bought.

---

## 1. Apple account and distribution

- [x] Apple Developer Program membership active (confirmed 2026-09-30)
- [ ] App Store Connect API key issued (Users and Access, Integrations, App Store Connect API).
      Needed if any of the below is to be automated rather than clicked.
- [x] Bundle identifier registered in the Developer portal, 2026-10-04 (Identifiers, App IDs, explicit ID,
      with Push Notifications capability enabled now even though APNs is build 2 work in W3)
- [x] App Store Connect app record created, 2026-10-04 (needs the final name, a SKU, primary language,
      and the bundle ID above)
- [ ] Signing sorted: Apple Distribution certificate and provisioning profile, or Xcode
      automatic signing confirmed working against the real bundle ID
- [ ] Internal TestFlight group created. Up to 100 App Store Connect users, no Beta App Review,
      available within minutes. **This is the primary Tech Week path** per the design doc, `### Calendar`, the paragraph
      beginning "Distribution for Tech Week was reversed", not the
      fallback. Each tester becomes a team member with a role, which is more access than a
      link implies.
- [ ] External TestFlight group created. Up to 10,000 testers, requires Beta App Review.
- [ ] Beta App Review metadata drafted: what to test, demo account credentials, contact email.
      Missing demo credentials is a common same-day rejection.
- [ ] Export compliance and encryption declaration answered
- [ ] Privacy manifest and App Privacy answers drafted. The same "Distribution for Tech Week was reversed" paragraph notes review runs slower for
      AI features, new SDK strings, and privacy manifest changes, which is why Oct 13 on the
      external link is a coin flip.
- [ ] Guideline 4.7 compliance note pre-written, so a rejection can be answered same day.
      Content per the design doc, `### Calendar`, the sentence beginning "Rejection recovery": the shell hosts the account holder's own HTML5 mini apps, loads
      no native code, and exposes no native platform APIs to them. Added 2026-10-04: the note
      must also answer guideline 2.5.2 by name, the rule Apple used against Replit, Vibecode
      and Anything in 2026.
- [ ] App name, subtitle, description, screenshots and review notes checked for wording. None
      may say app builder, app maker, native iOS apps, code export or App Store submission.
      Anything was removed for describing itself that way. Use Sidekicks: personal HTML5 mini
      apps inside one app.
- [ ] Guideline 2.5.2 enforcement re-checked in the week of the external submission. Last
      read 2026-10-04: Replit was back in the store from May 15 with no public explanation.
- [ ] First throwaway build uploaded end to end, purely to prove the upload pipe works before
      there is anything worth shipping through it

---

## 2. Repo

- [x] Private GitHub repo created under the final name: `BHUVAN-RJ/midas`, 2026-10-04. Fresh
      `git init` in `~/Desktop/jess`, because the folder sat inside a parent repo whose
      history belongs to a different project. The local folder is still named jess.
- [x] `docs/` and `CLAUDE.md` moved across
- [x] Initial commit pushed

## 3. Backend skeleton

- [x] Cloudflare Worker skeleton deployed, 2026-10-05, as `midas-api`. Stack is named in the plan: Hono on Cloudflare
      Workers with D1 and R2.
- [x] D1 database created and bound, 2026-10-05 (`midas`, binding `DB`)
- [x] R2 bucket created and bound, 2026-10-05 (`midas-bundles`, binding `BUNDLES`)
- [x] Health endpoint reachable from the phone, confirmed by the founder 2026-10-05

---

## 4. Control run (clock bound, start immediately)

One week running reminders and calendar entirely through ChatGPT Scheduled Tasks and Claude.
Per the design doc, `## The Assignment`, the paragraph beginning "Also, week 0, one week", the expected result is failure and the value is the failure list. If it does not
fail, the reminders wedge is dead and the honest product is the ownership and upkeep story
alone.

- [ ] Started, with a start date written down
- [ ] Failure log file created, one line per thing that could not be done
- [ ] Specifically recorded: what could not be edited, listed, restructured, launched, or
      notified properly
- [ ] Verdict written at the end of the week

This is the only item on this page that cannot be compressed by working harder. It takes a
calendar week whatever else happens, so a late start is a permanent loss.

---

## 5. Reading, both sides

Deliverable is one file, `docs/research/week0-landscape-notes.md`, with one sentence per piece
on what it changes about Midas. Per the design doc, `## The Assignment`, the paragraph beginning "Week 0 is the research week", nothing gets built until that file exists. The
against side matters most: every premise revised this month was revised by the against side.

### For

- [x] Pete Koomen, "AI Horseless Carriages" (koomen.dev, April 2025)
- [ ] Pete Koomen, YC Fall 2026 RFS "A Cloud for Small Software" (ycombinator.com/rfs)
- [ ] Adam Waxman, "Software for One" (ajwaxman.com, July 28 2026)
- [x] Alex Kirk, "Personal Software Needs a Home" (alex.kirk.at, May 14 2026)
- [ ] Fabien Girardin, "Software Gets Personal" (Medium, Próximo, January 2026)
- [ ] Ink and Switch, "Malleable software" (inkandswitch.com, June 2025)
- [ ] MCP Apps announcement and spec (blog.modelcontextprotocol.io, January 26 2026)

### Against

- [x] Andy Matuschak, "Apps and programming: two accidental tyrannies"
      (andymatuschak.org/tat, March 3 2026)
- [ ] Hacker News thread on "Software for One" (item 49096605, August 2026), specifically the
      maintenance, cost, and sideloading comments
- [ ] Jeremy Morrell, "Extensible Software in the age of LLMs", and its HN thread (item 49363668)
- [ ] The vibe-coding security record: the Wiz write-up of the Base44 authentication flaw, plus
      the 2026 figures on vulnerability rates in AI-built apps
- [ ] Glitch shutting down project hosting (July 8 2025) and the stated reasons

### Unplaced

- [x] "HCI professor video", watched. Identified 2026-10-04 as the Matuschak piece above
      (andymatuschak.org/tat), so it is an against and needs no separate sentence.

### Deliverable

- [ ] `docs/research/week0-landscape-notes.md` exists with a sentence for every piece above

---

## 6. Competitor test

Per the design doc, `## The Assignment`, first paragraph. One evening. Build a reminders app that is only for you, in each tool, and write
down the exact step where "just for me" breaks: public URL, login wall, no notifications, no
Siri, nowhere to keep it alive. That log is the first real P2 evidence and the v1 spec for what
the shell must do that they cannot.

- [ ] Lovable
- [ ] Bolt
- [ ] Base44
- [ ] Replit, added 2026-10-04
- [ ] By hand with Claude Code, added 2026-10-04, as the baseline
- [ ] Wabi, added 2026-10-04. Needs a Wabi 2.0 invite; without one the app allows nothing.
      Tests: build a reminders app, share it with one named friend, go offline, edit it after
      use, wait for a notification.
- [ ] Token usage and cost recorded per tool, as a statistic
- [ ] Break-point log written

Founder's plan as of 2026-10-04: this test runs in parallel with a stickiness test, building
the apps the founder and a few friends want and watching whether anyone keeps using them.

Investor note, 2026-10-04: a16z led Wabi's 20 million dollar round, and Garry Tan of Y
Combinator and Amjad Masad of Replit are angels in it. Decide before Oct 13 what is shown at
a16z Tech Week, and expect "how is this different from Wabi" as the first question on Nov 2.

## Schedule reality

Written 2026-09-30, updated 2026-10-04. W0 was budgeted Sep 25 to 27 and its gates are still
open on Oct 4, with no code written and build 1 due Thu Oct 8. Build 1 scope changed on
2026-10-04 (design doc, `## Architecture Decisions, 2026-10-04`): the generator and app editing
moved out, and three hand-written Sidekicks, cross-app read with consent, the notification
watcher and usage metrics moved in. That is more than the days left, which is why open
question 2 under "Pick up here" needs an answer first.

The shed order in the Re-plan (generated icons, launcher, status line) applied to the generator
build and no longer fits build 1.
