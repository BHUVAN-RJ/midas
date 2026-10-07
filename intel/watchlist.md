# Midas intel watchlist

Edit this file to change what the daily and weekly jobs watch.

## What Midas is

A user asks for a small personal app in their own words, Midas generates it, deploys it privately
(no public URL, no directory) inside an iPhone shell (SwiftUI + WKWebView), and keeps it working.
Mini apps are called Sidekicks. Differentiators the founder defends: the phone (home,
notifications, offline), private deploy to named people, one data store per person across apps,
upkeep, data export.

## Direct competitors (highest priority)

- **Wabi** (wabi.ai, Eugenia Kuyda, a16z): Wabi 2.0 messenger pivot, invites, Android/desktop,
  offline, data export, pricing (Wabi Max), funding, user numbers.
- **CriAI** (App Store id6797077582, solo founder Renato Cassola, Brazil): describe an app by text or voice,
  get a single-file HTML mini app running privately on the iPhone in an isolated web view with its own
  storage and no internet; credits for create/edit; invite-only until ~Oct 2026, public launch now.
  Closest to Midas's on-phone private shape. Watch: sharing, notifications, sync, pricing, traction.
- **Conjure** (id6791572856): closest feature set (sharing into named people's spaces, offline
  "when supported"). Watch weekly.
- Kiln (id6767986271), Blanks (id6744576554, Polsia), aSim (id6581479509, YC S21), Whip
  (id6758931714): same shape (host app running generated mini apps).
- MiniApps Store (Zoomerang), Build Minis, Sekai, Aippy, Miniceo, Bitrig, Meta Pocket: Apple
  precedent watch (live apps running generated software in-app). Easyapp.ai downgraded.
- 4.7 precedents (host apps running third-party web-code apps): Even Realities (id6747017725,
  Even Hub plug-ins for G2 glasses) and Mentra (id6747363193, MentraOS miniapps moving on-phone).
  Watch for: Apple pushback, how they handle 4.7.2 native access, store/SDK changes.
- 2.5.2 sentinel: Bloom (Android-first after Apple 2.5.2 / DPLA 3.3.1(B) rejection, App Clip
  sharing), Emergent iOS, Anything, Rork are off the US store; the tracker alerts if any return.
- Any new "mini app maker" app.

## App builders

- Replit (private publishing, MCP server), Lovable (agent integrations, internal publishing),
  Base44 / Wix (App MCP, Superagents, App Store wrapper), Google Opal (shutting down Nov 17, 2026,
  folding into Gemini Skills), Taskade.
- YC companies in the space: Floot (builds from inside Claude/ChatGPT via MCP), Emergent (unicorn,
  React Native/Expo output, iOS app removed), x1 and Fastshot (standalone App Store apps; check
  monthly). Deep Interactions and Vybe: team builders, quarterly. Watch for new ones and pivots.

## Platforms and assistants

- OpenAI: Dots, plugin extensions (sidebar home, panels; web/desktop, mobile unconfirmed),
  Sign in with ChatGPT, ChatGPT mobile app surfaces, Agents API.
- Anthropic / Claude: artifacts, MCP Apps, custom connectors, Claude mobile.
- MCP Apps spec (io.modelcontextprotocol/ui) changes.
- Composio.
- assistant-ui (YC W25, open-source chat UI kit, React Native since March 2026, Assistant
  Cloud): releases, MCP Apps rendering, mobile. Deep dive: `docs/intel/2026-10-07-assistant-ui.md`.
- Apple: App Review Guidelines 4.7 and 2.5.2, Mini Apps Partner Program, iOS 27 Siri / App
  Intents, WebKit / WKWebView capability changes (web push, service workers, background).

## The phenomenon

- personal software, small software, "software for one", malleable software, home-cooked apps,
  vibe-coded personal apps, AI mini apps; YC "A Cloud for Small Software" RFS and similar
  investor theses; security incidents in AI-built apps; essays and HN / Reddit threads.

## Personal-software demand (added 2026-10-07)

Report as facts with quotes; these are the people Midas is for.
- "Built it for myself first" posts: personal or friend-group apps later published (examples
  2026-10-06/07: Maroon campus macros, AmaNous on-phone TTS, Disc Duel on Base44, WellNest on
  Base44, a personal laser-engraving converter, a private photo vault). Note what they built it
  with, who it was for, and what they did next.
- Upkeep pain of throwaway personal tools: state, retries, stale data, duplicate alerts,
  notifications, "keeping it running" (example: r/quantfinance 2026-10-07, multi-source alert,
  "doesn't turn every alert into another small software project"). Quote the pain verbatim.
- Alphio (alphio.ai): AI trading assistant with plain-English conditions, proactive alerts
  (app / email / Telegram), Polymarket tracking. Watch: personal-alert use cases, pricing, traction.
- Odysseus (github.com/odysseus-dev/odysseus, PewDiePie, AGPL, ~90k stars) and Ajax (Qwen 3.5 9B
  fine-tuned for Odysseus tools): self-hosted local-first AI workspace. Watch: Ajax weights
  release, mobile / phone access, user-built tools or plugins, star growth.
- Followed threads: the collector pulls new comments on threads listed in
  intel/state/followed_threads.json (each with an "until" date). Report notable replies.

## Priority sources

- Hacker News (stories, Show HN, Launch HN). The collector covers title matches; also search HN
  for discussions of watchlist companies.
- Y Combinator: companies launching or pivoting into personal software / app building
  (collector diffs the YC directory; also check ycombinator.com/launches and Launch HN).
- Reddit: r/SideProject, r/vibecoding, r/nocode, r/iOSProgramming, r/ClaudeAI, r/ChatGPT,
  r/startups. The collector covers a keyword feed; if it failed, use web search with
  site:reddit.com.
- Company blogs, changelogs, docs, App Store listings, founders' X posts (primary sources).

## Watch items (tag "touches watch item N"; facts only, no evaluation)

1. Any assistant / MCP Apps host on a **phone** gaining local notifications, home-screen
   presence, or offline apps.
2. ChatGPT plugin extensions / app sidebar reaching the **mobile** app; Dots gaining texting or
   user-built apps.
3. Apple changing 4.7, 2.5.2, mini-app rules, or WebView capabilities.
4. Wabi: open sign-ups, Android/desktop launch, offline, data export, private sharing changes,
   funding or user numbers.
5. A new App Store app or YC company that generates private personal mini apps on the phone.
6. People describing the upkeep of a personal tool (state, retries, alerts, keeping it running)
   as the hard part, or asking for a lighter way to run throwaway personal software.
