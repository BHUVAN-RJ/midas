-- jess router (founder, 2026-10-21): every attempt of POST /voice/jess is logged in voice_logs
-- too, with what was chosen. Staging only from this branch; the founder applies it to live.
-- Apply with: node scripts/migrate.mjs --env staging|live
--
-- endpoint: "reminder-parse" (the old route; rows before this migration are null and mean the
-- same) or "jess".
-- sidekick_id, tool: the Sidekick and the tool the model chose ("reminders.add"), or
-- "midas.repair_request" / "midas.cannot_act". Null when no tool was chosen.
-- tool_input: the tool's arguments as the phone gets them (the when already worked out), JSON.
-- phone_outcome: what the phone reported afterwards (POST /voice/jess/outcome): "applied", or
-- "refused:<reason>" when the Sidekick's own check stopped it, or "failed:<reason>".
-- status keeps its CHECK: a repair hand-off is logged as 'done' with tool midas.repair_request.

ALTER TABLE voice_logs ADD COLUMN endpoint TEXT;
ALTER TABLE voice_logs ADD COLUMN sidekick_id TEXT;
ALTER TABLE voice_logs ADD COLUMN tool TEXT;
ALTER TABLE voice_logs ADD COLUMN tool_input TEXT;
ALTER TABLE voice_logs ADD COLUMN phone_outcome TEXT;
