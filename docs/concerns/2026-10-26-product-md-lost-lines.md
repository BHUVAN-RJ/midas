# Concerns: lines lost from docs/PRODUCT.md (2026-10-26)

On 2026-10-26 a script in the lead session (adding Bhumi's Import line, commit `4052627`) emptied the
working copy of `docs/PRODUCT.md`. It held 32 uncommitted lines from another session. The working
copy was later restored and builds 17-19 were committed on top (`90ea976`, `aebe102`, `91760d6`),
but those 32 lines are not in `main`.

## Open

- **Missing from `docs/PRODUCT.md`:** two founder items of 2026-10-24:
  1. Section 2, "### Plan additions, 2026-10-24: notification levels and layout (founder)", 28 lines
     (would sit near line 539).
  2. Section 6, "To do (founder, 2026-10-24), not started: **notification levels and layout A**",
     4 lines (near line 935).
  The plan itself is also in `docs/NOTIFICATIONS.md` (`47b0299`) and on branch
  `agent/notif-levels-shell`; only the PRODUCT.md copy is gone.
- **Where the text is:** git object `776004dbcb207fc59f202435f2ae3202195ce921` (the emptied working
  copy: `git cat-file -p 776004d`, lines 542-569 and 938-941), and
  `/private/tmp/claude-501/-Users-bhuvanrj-Desktop-Midas/83bb803a-aa9e-4550-ad3b-d82d7c2385b9/scratchpad/PRODUCT.recovered.md`
  (temporary; the git object is the lasting copy until `git gc`).
- **Who:** the lead session on `main` puts both blocks back into `docs/PRODUCT.md` (do not copy the
  whole file: it predates builds 17-19). Check with the founder first if
  `docs/NOTIFICATIONS.md` now supersedes them.
