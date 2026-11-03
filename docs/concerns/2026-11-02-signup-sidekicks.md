# Open concerns: starter Sidekicks for every account (2026-11-02)

Left by the signup-sidekicks agent. Branch `agent/signup-sidekicks`, on origin/main `73d987a`,
head `816ec37` plus this handoff commit. Not merged. All suites pass (backend 1355/1355, shell
1146/0, midas-intel 31, guard OK).

## 1. Merge (lead)

Ready to merge. Commit `066c51a` is titled "Reminders, To-Do, Water"; `b2aab5e` replaces that
order with Reminders, Water, To-Do (PRODUCT.md). Squash on merge for a clean history.

## 2. Live steps not run (founder, after the merge and staging)

Migration 0013 must be on the environment first. Pages only if not deployed there yet (each
refuses on live unless staging runs the same page):

```
cd ~/Desktop/Midas/midas/backend && npx wrangler deploy
cd ~/Desktop/Midas/midas/backend && node scripts/deploy-sidekick.mjs todo --env live
cd ~/Desktop/Midas/midas/backend && node scripts/deploy-sidekick.mjs hydration --env live
cd ~/Desktop/Midas/midas/backend && node scripts/assign-starter-sidekicks-to-everyone.mjs --env live
```

The script prints which starter pages are missing; accounts see them once deployed. DEPLOY.md §4
lists the script; its page list (§3.3, §4) still names only `reminders` and `care-reminders`.
Lead adds `todo` and `hydration` there if wanted.

## 3. One shell test failed once

`JessWorklogLinkTests.testThePastedHelperReadsTheFocusAndMarksTheRecordUnderTheRealCSP` failed in
one full run (test-guardian, 2026-11-01, "Midas Sim 2"), passed alone (9/9) and in the next full
run. No shell file touched on this branch. Watch for it again; pick up if it repeats.

## 4. Decided, no action

Make's Built can give back a Sidekick a person deleted (`make.ts:576`). Lead, 2026-11-01: leave it.
