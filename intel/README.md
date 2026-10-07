# Midas intel

Automated market and competitor intel for Midas. Output is plain Markdown in `docs/intel/`,
committed to this repo. gbrain (if you use it) indexes the repo as a source; the jobs never
write into gbrain directly.

## What runs

| Job | When | What it does | Output |
|---|---|---|---|
| daily | 07:00 and 19:00 | `collect_sources.py` gathers what is new (App Store, Hacker News incl. Launch HN, YC company directory, Reddit), then headless Claude Code triages it and searches the web | `docs/intel/<date>-<am\|pm>.md` |
| weekly | Sunday 09:00 | Claude Code summarizes the week's digests | `docs/intel/weekly/<year>-W<week>.md` |
| baseline | by hand, rarely | Claude Code reviews the full candidate set, not just what is new | `docs/intel/baseline/` |

Reporting follows the rules in the root `CLAUDE.md` ("How to work with the founder"):
information, not judgment; no threat ratings or recommendations; fatal-level news only.

## Files

| File | Purpose |
|---|---|
| `watchlist.md` | What is watched and why. Edit this to change coverage. |
| `collect_sources.py` | Deterministic collector: tracked App Store apps, keyword searches, the 2.5.2 return sentinel, HN, YC directory diff, Reddit RSS. No LLM, no API keys. |
| `baseline_inputs.py` | Dumps the full current candidate set for a baseline run. |
| `daily-prompt.md`, `weekly-prompt.md`, `baseline-prompt.md` | Instructions for the Claude Code pass of each job. |
| `run.sh daily\|weekly\|baseline` | Runs one job. Claude Code may write only under `docs/intel/` and `intel/state/`, and cannot run shell commands. |
| `install-schedule.sh` | Installs a direct launchd schedule. **Do not use on the founder's Mac mini**: launchd cannot read ~/Desktop there; the schedule runs through `~/code/midas-intel-runner/` instead (see below). |
| `tests/` | `python3 -m unittest discover intel/tests` (Reddit search + followed-thread parsing). |
| `state/followed_threads.json` | Reddit threads whose new comments the collector pulls until each `until` date; the daily Claude pass may add threads. |
| `state/`, `collected/` | Local per machine, gitignored: what has already been seen and reported, and raw collector output. |

## Setting it up on another Mac

Requirements: Claude Code logged in (`claude`), `python3`. Optional: the gbrain Claude Code plugin
(`/plugin marketplace add garrytan/gbrain`, `/plugin install gbrain@gbrain`).

```bash
intel/run.sh daily          # first run records a baseline in intel/state/ and writes a digest
intel/install-schedule.sh   # then schedule it
```

Run the schedule on **one machine only**. `state/` is local, so two machines would each report
the same events.

Logs: `~/Library/Logs/midas-intel/` (`launchd.log` catches failures before `run.sh` starts).

## Schedule on the founder's Mac mini

macOS blocks launchd jobs from reading ~/Desktop (every direct run failed 2026-10-05 to 10-07 with
`can't open input file`). The schedule opens `~/Applications/Midas Intel Runner.app`, a small
wrapper granted Desktop access only, which runs `~/code/midas-intel-runner/run-intel.sh`.
Manage it with `~/code/midas-intel-runner/schedule.sh production|test|status`. Verified 2026-10-07.

## Keep the repo where it is

gbrain binds the `midas` source to this folder's physical path (`~/Desktop/Midas/midas` on the
founder's Mac mini). Moving or renaming the folder puts the source into `recovery_required`, and
gbrain has no supported relocation: `sources writer transfer --self-transfer` only re-registers
the recorded path (tried 2026-10-05, then restored). If the folder must move, plan it with
`docs/architecture/topologies.md` in the gbrain package.

New digests are uncommitted until someone commits them. To index them in gbrain right away:

```bash
cd ~/Desktop/Midas/midas && gbrain sync --source midas --working-tree --no-pull --no-embed
```

## Status, 2026-10-05

Done: collector, daily job on Claude Code (tested 2026-10-04), landscape baseline
(`docs/intel/baseline/landscape-baseline-2026-10-04.md`, with a correction section at the top),
reporting rules.

Not done:
- Weekly job not yet tested; it needs a week of daily digests first.
- Digests are not yet pushed to a phone notification (possible via the founder's PWA on his Mac).
- Watchlist ids for Bitrig and Meta Pocket not found yet.
- The baseline report predates the reporting rules and still contains threat levels and
  suggestions.
