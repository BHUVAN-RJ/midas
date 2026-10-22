# Concerns from the jess-background agent (2026-10-22)

Out-of-brief findings while building "jess in the background, one result card, jess for everyone"
(`docs/PRODUCT.md`, founder 2026-10-22; brief midas-intel
`docs/plans/2026-10-22-jess-background-brief.md`).

## 1. A repair or grow request can be filed twice if the answer is lost (raised 2026-10-22)

The phone keeps every request on disk until it has a result. If iOS ends the background time and
the server's answer never reaches the phone, the request is sent again on the next open (with its
original time and zone). A tool call is never applied twice (the phone marks it applied in the same
turn it writes the ops). But a "repair" or "grow" answer has already queued a repair on the server
when it is sent; sending the request again can queue a second one. The window is the ~30 s of
background time running out mid-request. Fix if it shows up: the phone sends its request id with
`POST /voice/jess` and the server answers a repeated id from `voice_logs` instead of running it
again (needs a column and a migration).

## 2. Result cards are kept per server, not per user (raised 2026-10-22)

`midas-jess-results-<host>.json` holds the cards and unfinished requests. Signing out and in as
someone else on the same phone would show the first person's cards (and finish their unfinished
requests with the new session). Clear the file on sign-out if accounts are ever shared on a phone.

## 3. jess in a folder widget is drawn from an SF Symbol (raised 2026-10-22)

The home tile draws jess's orb. The widget extension does not have the orb (`JessOrb` is app-only),
so a folder widget shows jess's listing icon (`circle.circle.fill` on black), and tapping it opens
the Listening screen. `shell/Shared/SidekickIcon.swift` says chosen icons are drawn, not SF Symbols
(SF Symbols licence). Either draw the orb in `Shared` or leave jess out of the widget list.

## 4. The id "jess" is not reserved for deploys (raised 2026-10-22)

`deploy-sidekick.mjs` would accept a web Sidekick with id `jess`. The listing ignores R2 for jess, so
it would never show, but the bundle route would serve it. Refuse the id in the deploy script if
that matters.
