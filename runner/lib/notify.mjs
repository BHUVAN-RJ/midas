// Tells the founder on the Mac. For now a macOS notification (no click action); the real
// channel (call, iMessage) is built after the core (founder, 2026-10-13).
import { execFile } from "node:child_process";

function escapeForAppleScript(text) {
  return text.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

export function macNotification({ title, body, runCommand = execFile }) {
  const script = `display notification "${escapeForAppleScript(body)}" with title "${escapeForAppleScript(title)}"`;
  return new Promise((resolve) => {
    runCommand("osascript", ["-e", script], function finish(error) {
      // A failed notification never fails the job.
      resolve(error === null);
    });
  });
}
