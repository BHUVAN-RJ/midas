// The web Sidekicks every account gets besides jess and Make (founder, 2026-11-01: "every account
// gets a to do, reminders, hydration"). New accounts get them at sign-up (auth.ts); existing ones
// from scripts/assign-starter-sidekicks-to-everyone.mjs, which keeps its own copy of this list
// (a test checks the two match).
//
// Assigned whether or not a page is deployed yet: the catalog and jess leave out an assigned
// Sidekick with no base version, and its bundle answers 404, so an account simply sees it the
// moment its base is deployed. Sign-up never reads R2.
//
// Home order after jess and Make is this list's order: Reminders, To-Do, Water (founder,
// 2026-11-01). The catalog sorts by assigned_at, so each starter is assigned one millisecond after
// the one before it (starterAssignedAt).
export const STARTER_SIDEKICK_IDS: readonly string[] = ["reminders", "todo", "hydration"];

// The assigned_at for the starter at listIndex: the sign-up time plus listIndex milliseconds.
export function starterAssignedAt(signUpIso: string, listIndex: number): string {
  const signUpMs = Date.parse(signUpIso);
  const staggered = new Date(signUpMs + listIndex);
  return staggered.toISOString();
}
