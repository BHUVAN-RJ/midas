// The web Sidekicks every account gets besides jess and Make (founder, 2026-11-01: "every account
// gets a to do, reminders, hydration"). New accounts get them at sign-up (auth.ts); existing ones
// from scripts/assign-starter-sidekicks-to-everyone.mjs, which keeps its own copy of this list
// (a test checks the two match).
//
// Assigned whether or not a page is deployed yet: the catalog and jess leave out an assigned
// Sidekick with no base version, and its bundle answers 404, so an account simply sees it the
// moment its base is deployed. Sign-up never reads R2.
export const STARTER_SIDEKICK_IDS: readonly string[] = ["reminders", "hydration", "todo"];
