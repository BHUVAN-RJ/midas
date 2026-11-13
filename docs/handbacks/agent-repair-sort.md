# Hand-back: W2 Sort (`agent/repair-sort`), 2026-11-13

Brief: `docs/briefs/repair-lanes.md` section W2. Decisions: `docs/PRODUCT.md`, "Plan additions,
2026-11-13: repair lanes". Stage reached: **testing** (local suite, `wrangler dev` on 8792, real
OpenRouter benchmark). Nothing deployed.

## What was built

Every repair report from the phone is sorted in the Worker before any runner can claim it.

- `POST /repairs` stores the row (`status received`, `sort_status sorting`), stores the files, then
  calls Jev 1.14 (`POST https://openrouter.ai/api/alpha/decisions`, `typesafe/jev-1.14`) with the
  transcript (plus typed text), the Sidekick's name and `agent.description` from the person's
  current copy's manifest, and the drawing outline (stroke count and box, no picture). Questions:
  `lane` over the seven lanes, `guess` over the eight card guesses, wording exactly the benchmark's.
- Jev confidence below 0.7: Claude Haiku 5.5 (`anthropic/claude-haiku-5.5`, Chat Completions)
  decides with the same lanes and gives up to 3 guesses as JSON (its guesses first, then Jev's).
- Each call times out at 6 s. Timeout, HTTP error, unreadable answer, no key: lane `code`.
- Stored per report (migration `0015_repair_sort.sql`, additive): `sort_status`, `lane`,
  `sort_confidence`, `sort_model`, `sort_latency_ms`, `sort_cost_usd` (both summed over the first
  sort and the answer's sort), `sort_error`, `sort_question`, `sort_answer`, `sort_asked_at`,
  `sort_message`, `sort_alert`. Each sort also logs one JSON line (`event: repair-sort`).
- What each lane does:

| Lane | `status` | Phone gets | Runner | Other |
|---|---|---|---|---|
| code | queued | `{lane}` | claims it | founder `request_received` event, as before |
| setting, look | queued | `{lane}` | claims it (until W5/W6 build those lanes: up, never down) | same event |
| ask_back | received, `sort_status asking` | `{lane, question}` | no | 2-minute clock |
| not_a_request | received | `{lane, message: "Say or draw what to change."}` | no | none |
| shell_cant | received | `{lane, message: "<Name> can't do that yet. Sent to Midas."}` | no | push to the founder ("Can't do yet" / "<Name>: <words>"), result in `sort_alert` |
| jess_command | received | `{lane}` | no | see open question 1 |

- `POST /repairs/:id/answer` `{optionId}` or `{text}` (reporter only): the answer (option label or
  the words) is stored in `sort_answer` and the same request is sorted again with
  `Asked "What should it be?", they answered: "…"` added. After an answer, `ask_back` and
  `not_a_request` become `code`. Reply `{lane}` (plus `message` when the lane is `shell_cant`).
  400 unknown option or empty body, 404 not the reporter's, 409 no card waiting (already answered),
  410 dropped.
- Unanswered for 2 minutes → `sort_status dropped`, logged (`event: repair-question-dropped`).
  Swept when the runner polls `/repairs/jobs/claim` and when an answer arrives; no cron needed.
- `GET /repairs/:id` and the claimed job now carry `sort: {status, lane, confidence, model, answer}`.
  The repair agent must read `sort.answer` with the transcript (see "for the lead").
- A retry with the same `clientReportId` returns the stored reply (lane, card, message) without
  sorting again.

### Card options (W3)

`question = { text: "What should it be?", options: [ {id, label, icon} ×3 ] }`. Always 3: the
sort's guesses first, filled from the mockup's three (Other icon, Smaller, Remove). `icon` is an
SF Symbol name:

| id | label | icon |
|---|---|---|
| other_icon | Other icon | photo |
| smaller | Smaller | arrow.down.right.and.arrow.up.left |
| bigger | Bigger | arrow.up.left.and.arrow.down.right |
| other_colour | Other colour | paintpalette |
| remove | Remove | eye.slash |
| move | Move it | arrow.up.and.down.and.arrow.left.and.right |
| other_words | Other words | textformat |
| other_layout | Other layout | square.grid.2x2 |

## Deviations from the brief (and why)

- **No `status = 'sorting'`.** `repair_reports.status` has a CHECK listing six values; adding one
  means rebuilding the table, which the no-data-loss rails forbid (migration 0010 hit the same
  wall). The sort lives in `sort_status`; `status` stays `received` (never claimed) until a runner
  lane makes it `queued`.
- **`POST /repairs` reply** is `{ id, status, lane, question?, message? }`: `status` kept because
  the shell and existing tests read it today. `POST /repairs/:id/answer` adds `message` for
  `shell_cant` (the phone needs the line for the dark sheet).

## Files

- `backend/src/repair-sort-model.ts` (new): lanes, guesses, Jev and Haiku requests, `sortRequest`.
  Imports nothing, so the benchmark script loads it with plain node.
- `backend/src/repair-sort.ts` (new): placing a sorted report, the card, the founder push, the
  answer route, dropping stale cards.
- `backend/src/repairs.ts` (changed, outside the brief's file list, unavoidable): intake calls the
  sort; retry reply; claim sweeps stale cards; `POST /:id/answer` route; `sort` in the report JSON;
  `OPENROUTER_API_KEY` binding type.
- `backend/migrations/0015_repair_sort.sql` (new).
- `backend/scripts/sort-bench.mjs` (copied from the 2026-11-13 harness; lanes now imported from
  `src/repair-sort-model.ts`; new `--worker` mode runs the Worker's own sort; results go to
  `$TMPDIR/midas-sort-bench/`, never the repo).
- `backend/test/repair-sort-model.test.ts` (18 checks), `backend/test/repair-sort-route.test.ts`
  (14 checks). OpenRouter and APNs are stand-ins in both.

## Checks and what they caught

Mutation run (each change made, the new checks run, the change put back): confidence floor 0.6,
timeout 60 s, ask_back allowed after an answer, no sweep on claim, one word of lane wording,
Haiku failure taking Jev's lane, no founder push, any option id accepted. Every one failed at
least one check.

Full suite: see the result at the end of this file.

## Benchmark (real OpenRouter, the Worker's own code)

`node scripts/sort-bench.mjs --worker` over the 46 past requests, words and outline only:

| Run | Right | Quick lanes | Code sent down | Errors | p50 | p90 | Cost |
|---|---|---|---|---|---|---|---|
| 1 | 43/46 | 16/17 | 0 | 0 | 0.27 s | 3.20 s | $0.0032 |
| 2 | 44/46 | 17/17 | 0 | 0 | 0.25 s | 2.84 s | $0.0034 |

Misses (both runs went up a lane, never down): `42396937` setting → code (Haiku, same as the
research run); `bdd63740` look → ask_back (Haiku said look in the research run); run 1 only:
`6bcf16a1` shell_cant → code (Jev 0.73 this time, 0.65 in the research run, so Haiku was not
asked). The research note's 45/46 was one run; model answers vary run to run. The staging "Done"
line asks for 45/46 or better.

## How to try it

```
cd ~/Desktop/Midas/midas-worktrees/repair-sort/backend && npx vitest run test/repair-sort-model.test.ts test/repair-sort-route.test.ts
cd ~/Desktop/Midas/midas-worktrees/repair-sort/backend && node scripts/sort-bench.mjs --worker
```

Local server (`.dev.vars` holds `OPENROUTER_API_KEY`, gitignored; a local user `smoke` with
session token `smoke-token` and Water assigned is in the local D1):

```
cd ~/Desktop/Midas/midas-worktrees/repair-sort/backend && npx wrangler dev --port 8792
curl -s -X POST http://localhost:8792/repairs -H 'Authorization: Bearer smoke-token' -F sidekickId=hydration -F kind=change -F "transcript=Hey can you change this" -F 'strokes=[[[150,300,0],[250,400,50]]]'
curl -s -X POST http://localhost:8792/repairs/<id>/answer -H 'Authorization: Bearer smoke-token' -H 'Content-Type: application/json' -d '{"optionId":"remove"}'
```

Seen on `wrangler dev` with the real key: "Hey can you change this" → ask_back with a card;
"how are you" → not_a_request; "make the water drop blue" → setting (queued); "remind me every 20
minutes" → shell_cant; "add a weekly chart" → code. Answering the card → look, queued; a second
answer → 409.

## For the lead to add

1. **Deploy order:** migration 0015 on staging (`cd ~/Desktop/Midas/midas/backend && node scripts/migrate.mjs --env staging`)
   before the Worker; the new INSERT names `sort_status`, so the Worker fails on a database
   without 0015.
2. **Secret:** the sort reads the same `OPENROUTER_API_KEY` voice and jess already use (set on
   staging; check `wrangler secret list` on live before the live step). Without it every report
   goes to code. No `wrangler.jsonc` change, no new dependency.
3. **Runner (W4):** the claimed job's `sort.answer` is the person's answer to the card ("Other
   icon", or their words). Today's runner prompt reads only the transcript, so an answered request
   reaches the agent without the answer until W4 (or a one-line prompt change) reads `sort.answer`.
4. **Shell (W3):** `POST /repairs` can now take up to about 12 s in the worst case (Jev 6 s +
   Haiku 6 s); typical 0.3 s, slowest tenth about 3 s. Check the shell's upload timeout is above 12 s.
   410 on an answer means the card was dropped.
5. **jess-made repairs** (`queueVoiceRepair`, jess router) are not sorted: jess already decided
   it is a change. They have no `lane` (NULL).

## Open questions (founder or lead)

1. **jess_command:** the sort answers `lane: "jess_command"` and makes no job, but nothing runs the
   command yet (W2 and W3 do not say who). Options: the phone hands the words to jess, or the
   Worker runs the jess router itself. Until decided, such a request does nothing beyond the reply.
2. **setting / look before W5 / W6:** sent to the runner (queued) so they still get done. Say if
   they should instead wait unclaimed until those lanes exist.

## Full suite

`scripts/test-all.sh` in this worktree, 2026-11-13: ALL SUITES PASSED. Test guard 42 OK; backend
155 files, 1675 tests passed (typecheck clean); shell 1264 tests, 0 failures; midas-intel 31 OK.
