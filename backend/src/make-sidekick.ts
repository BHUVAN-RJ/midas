import { JESS_SIDEKICK_ID } from "./jess-sidekick";

// Make (founder, 2026-10-24; docs/briefs/make-contract.md section 1): two Sidekicks built into the
// shell, like jess. No R2 files, no tools, not repairable.
//   make        every person's: their requests, the thread with the founder, question cards.
//               Assigned at sign-up (auth.ts) and to existing users by
//               scripts/assign-make-to-everyone.mjs.
//   make-inbox  the founder's: every person's requests. Never in assignments; listed only for
//               the user named by MAKE_FOUNDER_USER_ID (a var per environment in wrangler.jsonc).
export const MAKE_SIDEKICK_ID = "make";
export const MAKE_INBOX_SIDEKICK_ID = "make-inbox";
export const MAKE_VERSION = "built-in";

export const MAKE_LISTING = {
  id: MAKE_SIDEKICK_ID,
  name: "Make",
  icon: { symbol: "plus", background: "#000000" },
  reads: [] as string[],
  version: MAKE_VERSION,
  builtIn: true,
};

export const MAKE_INBOX_LISTING = {
  id: MAKE_INBOX_SIDEKICK_ID,
  name: "Inbox",
  icon: { symbol: "tray", background: "#000000" },
  reads: [] as string[],
  version: MAKE_VERSION,
  builtIn: true,
};

// The name a person sees on the founder's side of a thread, as the title of every push sent to a
// person: "Make" (founder, 2026-10-31, docs/briefs/build-22-2026-10-31.md); change it here only.
export const MAKE_SENDER_NAME = "Make";

// The title of every push sent to the founder.
export const MAKE_INBOX_PUSH_TITLE = "Inbox";

// Sidekicks built into the shell: repair is not available for them, and a request cannot be
// "built" into one of them.
export const NATIVE_SIDEKICK_IDS: readonly string[] = [JESS_SIDEKICK_ID, MAKE_SIDEKICK_ID, MAKE_INBOX_SIDEKICK_ID];

export function isNativeSidekick(sidekickId: string): boolean {
  return NATIVE_SIDEKICK_IDS.includes(sidekickId);
}

export function isMakeSidekick(sidekickId: string): boolean {
  return sidekickId === MAKE_SIDEKICK_ID || sidekickId === MAKE_INBOX_SIDEKICK_ID;
}

// The founder's user id on this environment, or null when the var is unset or empty.
export function makeFounderUserId(env: { MAKE_FOUNDER_USER_ID?: string }): string | null {
  const configured = env.MAKE_FOUNDER_USER_ID;
  if (typeof configured !== "string" || configured.length === 0) {
    return null;
  }
  return configured;
}
