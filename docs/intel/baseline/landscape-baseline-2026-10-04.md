# Midas landscape baseline, 2026-10-04

> One-time landscape baseline, 2026-10-04. Inputs: `intel/collected/inputs-2026-10-04.md` (local).

One-time baseline. It judges every candidate against what Midas is: Sidekicks generated from a
request, run inside one iPhone shell, deployed privately to the user and named people, with
shell-owned notifications, offline from the op log, one store per person with cross-app read,
upkeep, reversibility and data export. It reads against the doc's Accepted risks (4.7, 4.7.x,
2.5.2), the Wabi record and the Survival Path.

Labels: **[C]** confirmed on a primary source (App Store listing or Apple lookup API, company
site, docs, YC page, founder's own post); **[R]** reported by press or an aggregator; **[U]**
unverified. "Removed" below means absent from Apple's US lookup API on 2026-10-04 [C]. Apple
gives no reason, and a storefront absence is not proof of a takedown.

## Top findings

1. **CriAI is the closest shipped shape and it calls itself an "AI App Maker".** It was released
   Sep 17 2026 and opened sign-ups Oct 2. It makes private apps on the iPhone that work offline,
   with no sharing. Its listing's "same expense tracker three times, three faces" copy matches the
   unverified r/SideProject lead [C listing; match is inference].
2. ~~**Apple's 2.5.2 record is worse than the doc says.**~~ **Withdrawn, see the correction below.** Bloom (YC) published that it got 2.5.2 and
   DPLA 3.3.1(B) rejections in March 2026 and pivoted to Android [C, bloom.diy blog]. Bloom's and
   Emergent's iPhone apps are both gone from the US store [C lookup], and Whip's founder cites
   "constant apple rejections" [R]. Emergent is a $1.5B company and still lost its listing.
3. **But in-app hosts are live today**, and the ones with traction do not call themselves
   builders. Wabi ("AI Messenger ... No building required"), Sekai and Aippy (about 24k ratings
   each, "create, remix, play" / "game maker") and aSim ("mini-apps") are all updated within the
   last two weeks [C].
4. **Nobody has Midas's full set.** No competitor found has one store per person with cross-app
   read, upkeep, reversibility or data export. Conjure comes closest on features (named-people
   shared spaces, offline "when supported").
5. **The platform watch item has not tripped, but MCP Apps already run on the phone.** Claude
   mobile renders MCP Apps in a native WKWebView, and artifacts with persistent storage have run
   on mobile since Oct 2025 [C, claude.com]. No user-built app on any assistant gets a local
   notification, a home-screen icon or offline use. Safari 27 added no web push for embedded web
   views [C, webkit.org], so shell-owned notifications remain the only route.

> **CORRECTION, 2026-10-04 (later the same night), replaces Top finding 2.** Finding 2 framed
> the 2.5.2 record as "worse than the doc says". That is wrong. Every enforcement found hit a
> **native or standalone app builder**: Replit and Vibecode (generated app previews), Anything
> (native iOS apps, code export, App Store submission), Bloom (Expo/React Native + Convex apps,
> rejected under 2.5.2 and DPLA 3.3.1(B) per its own Mar 23 post), Emergent (React Native/Expo),
> Rork (native SwiftUI). **No case was found of Apple acting against a host app that runs HTML5/JS
> mini apps under guideline 4.7.** Bloom is not a Midas analogue; its own section below already
> says so. Store absence (Bloom, Emergent, Rork) is not proof of a takedown.
>
> **The 4.7 route is demonstrably open.** Live precedents that run third-party or generated
> software inside one iOS host app:
> - **Even Realities** (id6747017725): Even Hub, a third-party plug-in store for G2 glasses with
>   ~50 plug-ins built "using web code" by 2,000+ developers, distributed inside the companion app.
>   v2.3.2, Oct 2 2026, notes "Redesigned Even Hub Discovery page" [C lookup].
> - **Mentra** (id6747363193): MentraOS mini app store. Apps ran in the cloud (no on-device code);
>   on Jun 9 2026 Mentra announced miniapps that "run locally on the phone, inside the host app"
>   in a JS runtime. App live, v3.1.1 Sep 17 2026 [C]; whether the on-phone runtime has shipped on
>   iOS, and on which engine, is [U].
> - Wabi, Sekai, aSim, Aippy, CriAI, Conjure, MiniApps Store (table in section 2).
>
> Why they fit: code is HTML5/JS in WebKit, which DPLA 3.3.1(B) allows when it does not change the
> app's primary purpose; the host's stated purpose is running those apps; none positions itself
> as a builder of standalone apps. Midas has the same shape. Open item: Even Hub plug-ins drive the
> glasses' display and input, which looks like exposing native capability; either Even Realities
> holds 4.7.2 permission or the host does all native work and plug-ins only declare what to show.
> Their developer docs answer it, and it is the model for the doc's device-connector direction.
>
> Programs: 4.7 needs no invitation or application. The Mini Apps Partner Program is optional,
> applied for by form, and only adds a 15 percent IAP commission tier for third-party mini apps.
> 4.7.2 native-API permission has no public process; Midas's fetch transport avoids needing it.
>
> Consequence for the Oct 8 note: lead with 4.7 and the purpose test of DPLA 3.3.1(B); answer 2.5.2
> by name; cite the live hosts above as the pattern, not the removed builders as the threat.
> Verified separately: Claude's mobile app renders MCP Apps in WKWebView (claude.com MCP Apps
> design guidelines), so finding 5 stands. Bitrig (YC S25, SwiftUI interpreter, approved after
> "back and forth" with Apple per its founders) did not appear in a US App Store search [U].

## 1. Tier 1: same shape as Midas

Differentiator key: phone home, notifications, offline, private named sharing, one store /
cross-app read, upkeep, reversibility, export.

### Wabi (id6747768928): threat HIGH, unchanged
- Listing "Wabi: AI Messenger", subtitle "Makes apps. Gets things done". v3.0.3, updated Oct 1,
  27 ratings, 4.6 average, requires iOS 26 [C lookup and listing]. The description says
  "No app hunting. No building required" [C]. v3.0.0 added group chats with friends and family,
  appointment, return and refund help, and proactive updates from chosen connections. v2.0.3
  (Jun 18) added "agentic mini-apps" that connect to your context [C, version history].
- Has: phone home (one host app), private named sharing (group threads), cross-app context
  (claimed), notifications ("proactive") [C/R].
  Lacks, or not shown: offline, upkeep, reversibility, export [U].
- Traction: no numbers public. Invite-only, with codes on X [R, TechCrunch Sep 29]. No news since
  Sep 29 of open sign-ups, Android or funding [U, nothing found].
- Why HIGH: same thesis, money, Apple-approved, and the investor overlap (see the Wabi record).
  New for the doc: the store version is 3.x while press says "2.0", and the US lookup gives a
  first release date of 2026-01-06.

### CriAI (id6797077582, Renato Cassola, Brazil): threat MEDIUM, technically closest
- Listing "CriAI: AI App Maker, No Code App", subtitle "Tailor-made apps, no coding". Released
  Sep 17 2026, v1.0.3 on Oct 4, 0 ratings, free, credits ($0.99 to $14.99) spent only on creating
  and editing [C lookup]. v1.0.2 notes: "Sign-up is now open ... 1,000 free credits" [C].
- Does: create from text or voice, edit by asking ("Make it cleaner"), "your apps run on your
  iPhone and work offline", "yours forever, no subscription" [C listing]. The site
  (criaiapp.com) says each app is isolated, data never leaves the app, and apps cannot send data
  over the internet [C]. Single-file HTML in a web view is [U]: the primary sources say only
  "isolated".
- Has: phone home, offline, editing. Lacks: any sharing, notifications, cross-app read, upkeep,
  export, sync or backup (none stated).
- Traction: none found [U].
- Why MEDIUM: it validates the private on-phone form with a solo founder. It has no sharing and
  no network, so the "to me and four friends" case and the store per person are untouched. Its
  title uses the exact "app maker" wording Apple cited against Anything. If Apple acts on it, that
  is the clearest signal for Midas's Oct 8 submission. It is also the likely author of the
  r/SideProject lead (matching copy) [inference].

### Conjure (id6791572856, Adrian Patterson): threat MEDIUM, closest feature set
- Listing "Conjure: AI App Builder", subtitle "Make custom mini apps, no code". v1.1.5 on Oct 2,
  first release Jul 25 2026, 0 ratings, free, no in-app purchases [C lookup and listing].
- Does: a chat of clarifying questions, then builds an applet in 1 to 2 minutes and notifies you
  when it is ready. Applets run in a "constrained viewer", share by link or "invite specific
  people into shared spaces", an optional public Gallery, "offline when supported", user-chosen
  cross-device sync, edit by chatting [C listing]. Website returned nothing [U].
- Has: phone home, private named sharing, partial offline, editing. Lacks: notifications from
  apps, cross-app read, upkeep, export (none stated).
- Traction: none. Why MEDIUM: it is the only listing that reads like Midas's build 2 sharing
  model. Watch it weekly.

### Kiln (id6767986271): threat LOW
- "Kiln - AI App Builder". Its pitch is closest to thesis 1: "instead of downloading a separate
  app for every little thing... Kiln builds it". It claims real SwiftUI components rather than a
  web wrapper, which is technically odd for downloaded code and worth a 2.5.2 note. Data stays on
  the device, sharing with friends since v2.0, a Marketplace, notification examples [C listing].
- v3 on Jun 17, 7 ratings, $9.99 to $29.99 a month [C]. No update since June [C], so possibly
  dormant.

### Blanks (id6744576554, Polsia Inc.): threat LOW
- "Blanks - AI App Builder", "personal software studio". Code runs in Blanks' sandbox, link
  sharing with collaborative editing, a social feed and chat rooms, version history, sync [C].
  131 ratings at 4.5, but the last update was Oct 30 2025 [C lookup]. Stalled.

### aSim (id6581479509, YC S21): threat LOW to MEDIUM
- "aSim: create & share mini-apps". Avoids "app builder" wording [C]. v1.269 on Sep 29 (it ships
  very often), 70 ratings at 4.6, Entertainment category, up to $149.99 a month for Pro [C].
  "Sims" run in-app and are shared to friends via a profile. They can call AI, gyroscope,
  location and weather APIs [C, YC page]. Team of 9, Seattle [C].
- Social and entertainment rather than private utility. Lacks offline, cross-app read, upkeep and
  export [U].

## 2. Apple precedent table: generated software running inside an iOS app

| App | Live in US store? | Last update | Self-description | Says "app builder/maker"? |
|---|---|---|---|---|
| Wabi | Yes | Oct 1 2026 | "AI Messenger", "No building required" | No (dropped) |
| CriAI | Yes | Oct 4 2026 | "AI App Maker, No Code App" | **Yes** |
| Conjure | Yes | Oct 2 2026 | "AI App Builder", "mini apps" | **Yes** |
| Kiln | Yes | Jun 17 2026 | "AI App Builder" | **Yes** |
| Blanks | Yes | Oct 30 2025 | "AI App Builder", "personal software studio" | **Yes** |
| MiniApps Store (Zoomerang) | Yes | Nov 26 2025 (v1.0 only) | "AI App Builder", single-file HTML, public feed | **Yes** |
| Miniceo | Yes | Sep 29 2026 | "AI App Builder" | **Yes** |
| aSim | Yes | Sep 29 2026 | "create & share mini-apps" | No |
| Sekai | Yes | Oct 2 2026 | "Create · Remix · Play", interactive content | No |
| Aippy | Yes | Sep 25 2026 | "Game Maker" | No (game maker) |
| Build Minis | Yes | Feb 7 2026 | games, art, toys | No |
| Whip (YC W24) | Yes | Jun 13 2026 | "Feed for AI Creations" | No; founder reports repeated rejections [R] |
| Easyapp.ai | Yes | Oct 3 2026 | "Mini Apps for Creators" (creator storefront web apps, not generated software) | No |
| Bitrig (YC S25) | Reported live | ? | runs generated SwiftUI through an in-app interpreter [R] | [U] |
| Bloom (YC X25) | **No** | last Mar 3 2026 | "Build Apps with AI" | Yes; 2.5.2 + DPLA 3.3.1(B) rejections [C, own blog] |
| Emergent | **No** | last Apr 5 2026 | "Vibe Code Apps" | Yes-ish [R] |
| Anything | **No** | removed Mar 26 and again in Apr 2026 | "mobile app builder" | Yes [R] |
| Rork | **No** (lookup empty) [C] | ? | builds native apps | Yes [U why] |

**What this proves.** Apple's approval process has repeatedly let through apps that generate
software and run it inside the app. Some of these say "AI App Builder" in the title (CriAI was
approved on Sep 17 2026, Conjure on Jul 25 2026). The apps with traction and ongoing updates
(Wabi, Sekai, Aippy, aSim) all avoid builder wording and present themselves as messenger,
entertainment or play.

**What it does not prove.**
- Approval at launch is not safety. Bloom passed review "for months" before rejections arrived
  [C], and Anything was restored and then removed again.
- Small apps with no ratings (CriAI, Conjure, MiniApps Store) may simply not have been looked at
  again.
- No case shows Apple explicitly accepting a 4.7 compliance argument for generated software.
- Every removed app produced standalone or exportable native apps, or advertised App Store
  submission (Bloom, Emergent, Anything, Rork). The surviving set all keep generated code inside
  the host. That supports the doc's positioning rule ("no code export, nothing leaves the shell")
  but is correlation, not a stated Apple rule.
- (Superseded by the correction at the top.) Implication for the Oct 8 note: cite Wabi/Sekai-style framing (personal mini apps inside one
  app), and name 2.5.2 and DPLA 3.3.1(B), which Bloom was cited under, alongside 4.7.

## 3. Tier 2: adjacent builders

- **x1 (YC F24).** Builds standalone App Store iPhone apps, guiding the user from plan to design
  to build to listing, screenshots and submission [C, YC page]. Public launch Aug 26 2026, #1 on
  Product Hunt [R]. Stack: mostly reported as React Native with Expo Go preview, TestFlight and
  RN export [R]; the Swift claim comes from one aggregator. No pivot found, so the founder's
  suspicion is not supported [R]. No own iOS app. Moving away from Midas's shape.
- **Bloom (YC X25, Zürich, $3.4M Moonfire [R]).** Generates Expo/React Native plus Convex apps.
  Shared apps open on iPhone as **App Clips** by link or QR, with no App Store or TestFlight [C,
  docs.bloom.diy]. That is private link sharing without a host app, a distinct and interesting
  pattern. The founder's "no updates in a year" is **refuted**: the changelog runs to May 28 2026
  and the blog to May 13 2026 [C]. It has been quiet since. Its iOS builder app (id6740775687) is
  gone from the US store, and its own post says 2.5.2 rejections pushed it to Android [C]. Not in
  Midas's shape (no host app, no store per person). Its main value is as a 2.5.2 data point.
- **Fastshot (YC F25).** Expo/React Native plus Supabase, publishes to the App Store and Play,
  Adapty subscriptions, "10,000+ builders" [C]. The YC page says Greece; Brazil is unsupported
  [C/U]. Low concern, confirmed.
- **Emergent (YC S24).** $1.5B valuation, $130M Series C on Jul 15 2026, about $120M run-rate,
  12M+ apps built [C/R]. The founder's "no mobile" is **wrong**: it generates React Native/Expo
  apps (80 to 90% of new projects are mobile), tested by QR and published by users to the stores,
  and it launched an iOS builder app on Feb 17 2026 [R, TechCrunch]. That app (id6748029391) is
  now gone from the US store [C lookup]. Not moving toward a host app.
- **Floot (YC S25).** Full-stack web apps built from inside Claude, ChatGPT or Cursor via an MCP
  connector, with the AI paid by the user's chatbot plan [C]. Now also publishes to iOS and
  Android [R]. A pivot risk only in the doc's thesis-1 sense (asking inside an assistant).
- **Lovable.** iOS app (id6757471107) "Build Apps With AI" is a builder remote; output is public
  web apps; $600M ARR [C/R]. Not moving.
- **Replit.** Back to regular iOS updates (2.200.4 on Sep 14). The listing says "app builder" and
  "public URL" [C]. Nobody has disclosed what Replit changed for Apple. Not moving.
- **Base44 / Wix.** One native wrapper per app with push notifications in store builds, no
  offline stated [C docs]. Superagents [R]. $200M ARR and 10M users reported Aug 2026 [R]. The
  closest builder to "phone plus notifications", but one store submission per app.
- **Vibecode.** Now "Website Builder", Education category, "learn to code... see and edit the
  source code" [C]. That reads as a deliberate fit to 2.5.2's education exception (source
  viewable and editable). Out of iOS app generation.
- **Anything.** Still absent from the store; works through iMessage and desktop [R/C lookup].
- **Rork.** Rork Max builds native SwiftUI apps and submits to the App Store; its listing is
  absent from the US lookup [C], reason unknown.
- **Taskade Genesis.** "AI App Builder"; apps live at private, password-protectable links,
  web-hosted [C]. Flat per-workspace pricing [R]. Conceptually near ("living software") but no
  phone runtime.
- **Others.** v0, Michelangelo, VibeKit, Appy Pie, LastApp, Rocket, OnSpace, FlutterPilot,
  Codera, Snapp and Vulk all produce web or standalone apps, and the phone app is a remote [C/R].
  None is moving toward a host.

## 4. Tier 3: platforms and teams

- **OpenAI.** Plugin extensions are developer-built. Sidebar entry points are reported on mobile
  [R], file viewers are desktop-only [R]. Dots roll out on web, mobile and desktop for Pro and
  Business Premium, with texting connected from desktop [R; help page unfetchable]. Canvas tools
  can be shared as links but have no persistent mobile home [U]. Watch item 2 is half met: a
  sidebar home on mobile, but no user-built apps.
- **Anthropic.** MCP Apps are "available in Claude on mobile, web and desktop" and render in a
  native WKWebView on iOS [C, claude.com, Jan 26 2026]. Artifacts have run on mobile since Jul
  2025, with persistent storage since Oct 2025 [C]. No notifications, home icon or offline.
  **This corrects the doc's "No phone" line** in the MCP Apps section: the phone host exists, and
  what is missing is lifecycle.
- **Google.** Opal and Gems made by Labs turn off Nov 17 2026, with no migration and files left in
  Drive [C, Opal FAQ]. Opal could share with named people, so a Midas-like sharing surface is
  exiting. Gemini Skills (Oct 1) are prompts, not apps [R]. Gemini Spark is an always-on agent,
  not a builder [R].
- **Apple.** Guidelines revised Jun 8 2026 (the doc says Jun 9), with nothing on 2.5.2 or 4.7 [C].
  No later change aimed at mini apps found. Safari/WebKit 27 widened WKWebView APIs but added no
  push for embedded web views [C]. The Mini Apps Partner Program is unchanged [R].
- **Meta.** Pocket (from the Gizmo team) makes vibe-coded "gizmos", games and simple apps in a
  public remix feed. It reached US users in Aug 2026 [R]. Entertainment, public, not utility.
- **Team builders vs the Survival Path.** Deep Interactions (YC Spring 2026) is a team product
  builder plugged into Slack, Figma and GitHub, waitlist only, explicitly "not solo AI" [C]. It
  starts at step 4 of the ladder, not step 1, so it is no threat to the consumer wedge. Vybe is
  Slack-native company agents [C]. Taskade's flat per-workspace pricing and Glide's
  personal-to-team plans are the closest existing versions of steps 2 and 3 [R]. None is on the
  phone.
- **"An app of one's own."** Philip Ilic Thomas, dated **2025-05-16**, not 2026 [C]. His own
  "Junk Drawer" is a private Rails app with one login and Signal notifications. No product since;
  his Oct 2026 newsletter mentions "Bell", an SMS bot for his posts [C]. A thesis signal, as the
  founder said.

## 5. Dismissed (noise)

- Games and mini-game collections: Mini Golf, Mini Militia, Mini Motor Racing, Mini Soccer,
  Everyday Puzzles, Mini Games, Skin Maker.
- Chatbots and companions: Nova, Genie, Savvi, Chatbot App, AI Chat, CHAI, Dippy, Kindroid,
  Replika, Otherhalf, Vidy, Talkie Lab, Lloyd, NextGen, Virtual Talk, Claudia, LM Mini, Kimi,
  DeepSeek, Grok, Manus, Runable.
- Messengers and browsers: WhatsApp, Messenger, Telegram, iMe, nandbox, WhizAI, Azar, Opera,
  Yandex.
- Finance, loans and credit: Bright, Self, Upstart, iLoan, My Personal Loan, MoneyWiz, Money
  Monitor, Quick Checkbook, Quicken, Easy Life, BBK BanKey.
- Business, HR and field apps: Jobber, Namely, eHub, PTminder, PatientNow, Shpper, Amare,
  AppSheet.
- Old template app makers with no generation-in-host: App Studio, iGenapps, Onespot, NucleApp,
  App Maker (2020), Universe.
- Coding education: Sololearn, Encode, KODiQ, DeepLearning.AI.
- Remote-terminal and agent IDEs: CodeMote, Sessix, Viber, Vicoa, NiHao, IDE for Claude Code,
  Vibe Coding Studio/Toolkit/Agent.
- Prompt helpers and copycat listings: AI App Builder Architect, Lovable Guide, "Base44 - Code
  with AI" (Zenta Paegle, not Base44), Make-It.
- Hardware, media and utility apps: MINI (BMW), instax, Phomemo, Print Master, Tiny Scanner,
  MinimaList, icon and ad makers, video makers, ChibiStudio, Fitbod, Gym Life, MuscleUp,
  Cultivate, Patterns, personal journals, password managers.
- Mini App Central: a curated catalog, no generation.
- YC enterprise and internal builders, dead or off-topic: Windmill, Jet Admin, Glide, weweb,
  Blitz, Vortexify, Dropbase, Chaser, Livedocs, Humand, Hilos, AppX (creator apps), Ruta, UpLabs,
  Parse, Zillabyte, Mocha (acquired), Anima, CreativeMode, Tweeks, Rosebud.
- Other YC builders: vly.ai (acquired by Freebuff [C]) and Vibe (vibe.codes, no identifiable
  product [U]).
- Sparkles: non-engineers' pull requests to existing code [C].

## 6. Not in the design doc yet (suggestions only)

1. **Accepted risks, the 2.5.2 enforcement record:**
   - Bloom's March 23 2026 post naming 2.5.2 plus **DPLA 3.3.1(B)** and describing rejections of
     features approved for months.
   - Bloom and Emergent iPhone apps absent from the US store.
   - Whip's reported repeated rejections.
   - Bitrig's interpreter approach reportedly surviving.
   - The education exception in 2.5.2 that Vibecode moved into.

   Consequence: the compliance note should cite 3.3.1(B) as well as 2.5.2 and 4.7.
2. **Accepted risks / positioning:** the precedent table above. Live in-app hosts exist, including
   ones titled "AI App Builder". The ones with traction avoid builder words, and Wabi's listing now
   says "No building required".
3. **MCP Apps, In Plain Terms, and the Field correction:** Claude mobile renders MCP Apps in a
   native WKWebView (Jan 2026), and artifacts with persistent storage run on mobile. "No phone"
   should read "on the phone, no lifecycle".
4. **Landscape Update 2026-09-24, Competitor movement:** CriAI (private, offline, on-phone, Sep
   17 2026), Conjure (named-people shared spaces), Kiln, Blanks, aSim, Whip and Meta Pocket. Also
   correct "Build Minis" to games and toys.
5. **Competitor Record: Wabi:** the store version is 3.0.x, it requires iOS 26, the US first
   release date is Jan 6 2026, v2.0.3 (Jun 18) added agentic mini apps, and the listing carries
   the "No building required" wording.
6. **Infrastructure, phone moat:** Safari 27 adds no web push for embedded web views. This
   confirms the shell-owned notification design.
7. **Landscape Update 2026-10-03, Google:** Opal supported sharing with named people. Its
   Nov 17 shutdown removes the one platform surface with that property.
8. **Survival Path:** Deep Interactions, Vybe and Taskade as evidence that team builders start at
   step 4. Taskade's flat per-workspace pricing is a counter-model to Tailscale's per-user ladder.
9. **Accepted risks, date fix:** the guidelines update is Jun 8 2026 per Apple and press, not
   Jun 9.
10. **Sharing (build 2):** Bloom shares generated apps as **App Clips** with no install. That is a
    possible answer to the doc's "first-time recipient must pass through TestFlight" problem once
    on the App Store. It needs checking against App Clip size and code rules before anyone relies
    on it.

## 7. Watchlist changes

- **Add, Tier 1:**
  - Conjure, id6791572856 (weekly)
  - Kiln, id6767986271
  - Blanks, id6744576554
  - aSim, id6581479509
  - Whip, id6758931714
- **Add, Apple precedent watch** (version and availability only):
  - Sekai, id6504506653 (already tracked)
  - Aippy, id6749073777
  - Build Minis, id6756137814
  - Miniceo, id6747975557
  - Bitrig (find its id)
  - Meta Pocket
- **Add, 2.5.2 sentinel:** alert if CriAI (id6797077582), Conjure or MiniApps Store disappears or
  renames. Also alert if Bloom (id6740775687), Emergent (id6748029391), Anything (id6751247034)
  or Rork (id6746410361) **return** to the store.
- **Change:** Bloom moves from "build and share mobile apps" to "Android-first after Apple
  rejections, App Clip sharing". Floot moves to "builds from inside Claude/ChatGPT via MCP".
  Emergent: note mobile output and the removed iOS app.
- **Downgrade or remove:** Easyapp.ai (creator storefront, not a peer), Deep Interactions and Vybe
  (move to a team-ladder note, check quarterly), Fastshot and x1 (monthly).
- **Remove:** the r/SideProject lead, resolved as probably CriAI.
