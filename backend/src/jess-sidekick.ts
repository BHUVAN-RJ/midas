// jess, a Sidekick every user has (founder, 2026-10-22): assigned at sign-up and to every existing
// user (scripts/assign-jess-to-everyone.mjs). It is built into the shell (the Listening screen),
// not a web bundle: no R2 files, no tools, not repairable. Listed first, from this constant.
export const JESS_SIDEKICK_ID = "jess";
export const JESS_VERSION = "built-in";
export const JESS_LISTING = {
  id: JESS_SIDEKICK_ID,
  name: "jess",
  icon: { symbol: "circle.circle.fill", background: "#000000" },
  reads: [] as string[],
  version: JESS_VERSION,
  builtIn: true,
};
