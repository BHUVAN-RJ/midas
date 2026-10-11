# Writing for Midas screens

Rules for every word a person sees in the Midas app and in every Sidekick: titles, buttons,
sheets, errors, empty states, summaries, notifications. Read this before writing or changing any
on-screen text, and before generating a Sidekick. Founder, 2026-10-10.

What not to say in public copy about Midas (pitches, App Store text) is a separate list: midas-intel
`docs/word-list.md`.

## The rule

**Say the action. Stop.** If the title and the button already tell the person what happens, add
nothing else.

Founder's example (2026-10-10), the Apple Reminders import sheet:

| Before | After |
|---|---|
| Title "Bring in your Apple Reminders" | "Import Apple Reminders" |
| "Midas reads your lists and reminders on this iPhone and adds them here. Nothing in Apple Reminders is changed." | (removed) |
| "Already brought them in from your Mac? Anything that changed on your iPhone is updated." | (removed) |

## Rules

1. **Cut every word that does not help the person act.** No explanations of how it works, no
   reassurance ("nothing is changed"), no "we", no "please", no "sorry", no "your" where the
   noun alone is clear ("Lists", not "Your Lists"). People scan: 79% scan, 16% read word by
   word; halving the words made pages 58% easier to use (Nielsen Norman Group).
2. **Titles: a few words, one line.** Name the thing or the action: "Import Apple Reminders",
   "Delete List?". Never "Error" alone.
3. **Buttons: a verb, one or two words, naming the result.** "Import", "Delete", "Save",
   "Try Again". Never "OK" unless the screen only informs; never "Yes"/"No"; the way out is
   always "Cancel" (or "Not Now" before a permission prompt). Same step, same word everywhere.
   While working, the label says so: "Importing…".
4. **Message lines only when the title and buttons are not enough.** Never explain what the
   buttons do. Never explain the interface; fix the interface.
5. **Results: past-tense verb plus the count.** "Imported 1,449", "Updated 12", "Up to date".
   No "Successfully", no thanks.
6. **Errors: what failed, then what to do.** Title names it ("Import Failed", "Can't Connect"),
   the button fixes it ("Try Again", "Open Settings"). No "Something went wrong" when the
   failure is known; no codes, no blame, no "oops", no "invalid".
7. **Empty states: a short headline and one action.** "No Reminders" plus the add button.
   15 words at most.
8. **Destructive actions: the verb on the button, the safety in the system.** "Delete List?" /
   "Delete" / "Cancel". Prefer undo over a confirmation. Ask only for rare, permanent actions.
9. **Permissions: ask when the feature is used, never at launch.** A screen before the iOS
   prompt has a title and one "Continue" (plus "Not Now"), no paragraph.
10. **iOS permission text (`NS...UsageDescription`) is the one place a full sentence is
    required.** App Store guideline 5.1.1(ii): it must "clearly and completely describe" the use,
    usually with an example. One short active sentence, ending with a period, naming what Midas
    does with it: "Midas imports your Apple Reminders lists and reminders into your Reminders
    Sidekick." Too short gets rejected ("To use reminders.").
11. **Capitalization (Apple style):** buttons and fragment titles in Title Case ("Try Again",
    "Import Apple Reminders"); full sentences in sentence case with a period. No period on
    titles, buttons or labels.
12. **Numbers as numerals,** commas from 1,000 ("3 lists", "1,449 reminders").
13. **Plain words, the same word for the same thing.** "Import", not "Bring in"; "Can't", not
    "Unable to"/"Cannot". No technical words on screen (sync, server, record, request, store).

## Common swaps

| Instead of | Write |
|---|---|
| Bring in / Pull in | Import |
| Couldn't reach Midas | Can't Connect + "Try Again" |
| Something went wrong. Try again. | Name what failed: "Import Failed" + "Try Again" |
| Are you sure you want to delete this list and all of its reminders? | Delete List? + "Delete" |
| You have no reminders yet. Tap + to create your first reminder. | No Reminders |
| Successfully imported! | Imported 1,449 |
| OK / Yes / Confirm (on a destructive alert) | Delete / Remove |
| Continue with a passkey | (the action itself: "Get Started") |

## Sources (fetched 2026-10-10)

- Apple HIG: Writing, Alerts, Action sheets, Buttons, Onboarding, Privacy
  (developer.apple.com/design/human-interface-guidelines/…)
- App Review 5.1.1 purpose strings: developer.apple.com/help/app-review/guideline-reference/5-1-1-purpose-strings
- Nielsen Norman Group: nngroup.com/articles/how-users-read-on-the-web/,
  …/concise-scannable-and-objective-how-to-write-for-the-web/, …/error-message-guidelines/
- Microsoft Writing Style Guide (top 10 tips), Windows UX error messages; Google Material
  communication codelab; GOV.UK writing for user interfaces, error message, confirmation pages;
  Shopify Polaris actionable language; Mailchimp style guide; Atlassian error messages and empty
  states.
- Apps: Things 3 ("Import Now", reassurance only in its help article), Apple Notes ("Import to
  Notes?" / "Import", no summary text), Apple Reminders ("Delete List", safety in Recently
  Deleted), WhatsApp permission text (one sentence naming the benefit).
