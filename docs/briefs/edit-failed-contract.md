# Edit could not be made: contract (build 22, 2026-10-31)

Decision: `docs/briefs/build-22-2026-10-31.md`, "Words": when an edit could not be made the person sees
**"Check back in some time."** and the founder is alerted (push plus the job in his Make inbox with
what was asked, why it failed and the job link); he fixes it by hand and publishes.
Server: `agent/edit-failed-store` (`backend/src/edit-failed.ts`, `repairs.ts`, `make.ts`). Shell reader:
`agent/edit-voice`. No migration. Code names stay `repair`.

## 1. What the app reads (edit-voice)

Nothing new to call. The existing routes carry it:

| Where | Field | Could not edit |
|---|---|---|
| `GET /repairs/notices` | `kind` | `couldnt_fix` (unchanged) |
| | `text` | `"Check back in some time."` (was "The update could not be made.") |
| | `summary` | always `null` (the founder's reason never reaches the person) |
| `GET /repairs/:id` | `status` / `result.kind` | `failed` / `couldnt_fix` |

Card state: `couldnt_fix` = **Not Done** (home shows it until swiped away). Already There
(`already_there`) is not a failure.

**Later turn to fixed.** When the founder fixes it by hand, the same report gets a second notice:
`kind: "fixed"`, `text: "The update you requested is done."`, `summary`: the founder's one-line plan,
same `reportId` / `clientReportId`. `GET /repairs/:id` then says `deployed_live` / `fixed`. The shell
should move that card from Not Done to Done (and off home) when a `fixed` notice arrives for a report
it already showed as Couldn't Fix.

Show the server's `text`; do not hard-code the words in the app.

## 2. Founder alert (server, in the same D1 batch as the failed status)

Fires on every `couldnt_fix`: runner posts `failed` (from `running` or `fix_ready`), or the lease ran
out `MAX_ATTEMPTS` times. Not on `no_change`.

Founder's `make-inbox` store (`MAKE_FOUNDER_USER_ID`; nothing when unset):

| Key | Value |
|---|---|
| `person:<u>` | as in the Make contract (written once) |
| `req:<u>:edit-<report id, no dashes>` | `make.request`, `title` "`<sidekickId>: <what was asked>`" (200), `status` `sent`, plus `editReportId`, `editSidekickId` |
| `message:<u>:edit-<hex>:fail<16 hex>` | `make.message`, `from` `person`, text below |

Message text:

```
Could not edit <sidekickId>.
Asked: <transcript, then typed text if different>
Why: <runner reason>: <runner detail>
Job: ~/Library/Application Support/midas-runner/log/<report id>
Report: <report id>
```

Push: a `make_events` row `editfail:<report id>`, audience founder, kind `message`, title "Inbox", body
"`<name> · <sidekickId>: <first line asked>`" (120). Payload `make: {kind: "message", requestId:
"edit-…", userId: <u>}`, so the existing tap opens that inbox thread. Op and event ids are fixed by
the report id: stored once.

## 3. Founder fixes it by hand

1. Fix the person's copy and publish it (`deploy-sidekick.mjs <id> --env live --user <u> --dir …`).
2. In the Inbox thread: reply and status buttons work as usual, but **nothing is copied to the
   person's Make store** (edit threads live only in the inbox; ids starting `edit-` are never a
   phone's own request id).
3. Tap **Built** (pick the Sidekick, type the one-line plan). The server marks the report
   `deployed_live` / `fixed` with the plan as summary and queues the person's `fixed` notice (once;
   only if the report is still `couldnt_fix` and belongs to that person). No Make Built screen, no
   assignment change for the person.

## 4. Limits

- The job link is a path on the Mac mini (where the runner keeps the job's log), not a web link.
- A jess request waiting on the failed edit stays Not Done after the founder's fix (jess-pending is
  not re-run).
