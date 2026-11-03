# Concerns: onboarding, sign in on the Midas popup (2026-11-01)

Brief: `docs/briefs/onboarding-build.md` (update 2026-11-01, section 7).
Branch `agent/onboarding-design`, commits `bd047c7`, `f9dfa1f`, `ac99dd1`, `abbc6b2`, all on main
(fast-forward). Suites at hand-back: guard 42 OK, backend 1254 passed, shell 1141 / 0 failures
(Midas Sim 2), midas-intel 31 OK.

## Open

- **Not seen on a phone or the simulator:** typing a name, the popup lifting above the keyboard,
  a real passkey sheet (create and sign in), haptics, the Reduce Motion path. Keyboard lift is
  covered by `OnboardingSignInPopupTests`. Pick up: founder, on Midas Test.
- **Defaults taken, not asked (founder may change):** closing the passkey sheet returns to the
  popup; app closed before signing in → next open shows WelcomeView (also after Sign Out); auth
  errors show in red under the popup; icon blur 4 pt; returning users (Sign In) see the four
  cards once per phone.
- **`scripts/test-all.sh` shell step fails here:** default simulator "iPhone 17" is missing on
  this Mac (also in `2026-10-31-edit-failed-store.md`). Ran with `MIDAS_SIMULATOR="Midas Sim 2"`.
- **`scripts/sim.sh` untracked in this worktree.** Not made by this task; left alone.

## For the lead (files a worktree may not edit)

- `docs/PRODUCT.md` (~line 1428) still says "The personal touch your apps needed." and does not
  say sign in sits on the popup. Record: line is "The personal touch your apps need" (no full
  stop, typed out); after it the popup holds Name, Get Started and Sign In; icons behind blur;
  WelcomeView only for a signed-out phone after the intro (founder, 2026-11-01, "We're merging 1
  and 2 into one"). midas-intel design doc already has it (`80429af`). Lead moves it.
