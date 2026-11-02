# Account recovery: leftovers (agent/account-recovery, 2026-11-02)

Decision (founder, 2026-11-02): W1 only. `/support` gets "Lost passkey" / "Email
bhuvanrj73@gmail.com with your Midas name." Nothing in the app. Details and the options not chosen:
`docs/CONCERNS.md` §5.

For the lead:

1. **PRODUCT.md** (lead-only file): add the decision to "Plan additions, 2026-10-31: build 22",
   the App Store bullet, and to the midas-intel design doc (same session, per CLAUDE.md).
2. **Deploy:** the line appears on `/support` only after the server deploy on staging, then live
   (`docs/DEPLOY.md`). It rides the build 22 pre-upload server deploy; no app build needed.
3. **No give-back path exists yet.** When a recovery email arrives, the founder can check the
   person but there is no script to attach a new passkey or copy their data. Choose A1/A2/A3
   (CONCERNS §5) at that point.
4. **Name taken on Get Started:** a person who lost their passkey and types their old name gets a 409
   "that name is taken" from the server, which the shell shows as the generic "Can’t create
   account. Try again." (AuthModel.swift; no 409 case), with no hint of recovery. Left as is (founder: not in the app).
