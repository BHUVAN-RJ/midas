# AI consent: notes for the lead (2026-11-02, branch agent/ai-consent)

Founder decisions, 2026-11-02 (mockup `docs/mockups/ai-consent-2026-11-02.html`):

- **A1:** "Allow AI?" once in onboarding, after the four teaching cards, before Home. Anyone signed in
  before this build (skips onboarding) sees it once on first open.
- **D1:** after Not Now, the same screen comes up at each jess or Edit use until Allow.
- Privacy Policy on the screen opens `/privacy`.
- Providers named (OpenRouter, Anthropic), as `/privacy` already does. Default; the founder did not
  object.
- AI switch in Settings (approved in the build plan): off stops jess and Edit, on shows "Allow AI?".

For the lead to carry into `docs/PRODUCT.md` §6 and the midas-intel design doc (worktree agents may
not edit PRODUCT.md): the AI consent item is built on this branch, with these decisions.

What was built (shell only, no server change):

- `shell/Midas/AIConsent.swift`: the answer (UserDefaults `midas.aiConsent.answer`), the rules, the
  center (`run` / `allow` / `decline` / `askDismissed` / `setAllowed` / `forget`), the screen and
  the sheet.
- RootView shows the screen in place of Home until answered; signing out forgets the answer.
- jess: `VoiceReminderFlow.request()` asks before the Listening screen opens.
- Edit: the pill's Send calls `RepairSession.sendWhenAllowed()`; Not Now keeps the layer open.
- Backstop: jess, voice-parse and Edit uploads use `ShellServices.aiRequestSessionToken`, which has
  no token until Allow, so no request reaches the server before consent even if a screen forgot to ask.
  A queued Edit report waits in the outbox until Allow.
- Settings: an "AI" switch between the Sidekick list and Sign Out.
- Tests: `shell/MidasTests/AIConsentTests.swift` (21). Checked that 13 of them fail with the gates
  removed.

Open, not done here:

- The guard suite (`tests/guard`) and the midas-intel suite could not be run from this session: the
  test guard hook blocks those commands. This branch does not touch either. The lead's run of all
  suites covers them.
- Not tried on a phone yet. Midas Test on the founder's phone: onboarding → cards → Allow AI?; Not
  Now → jess orb → sheet; Edit Send → sheet; Settings switch.
- The answer is per install, not per account (signing out clears it). A second phone asks again.
