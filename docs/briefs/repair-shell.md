# Brief: repair-shell (iPhone: gesture, drawing, voice, send)

Read `docs/briefs/repair-contract.md` first. No dev port (shell); use the Simulator, not the
founder's phone (it runs the TestFlight build on live).

Founder, 2026-10-13: the gesture is a scribble, two or three zigzags, anywhere on the screen; it
should feel always on. The founder records the exact shape on
https://claude.ai/artifact/KziLctetheGwreYtvfdfQ7 (points `[x, y, ms]` in iPhone 16 points); the
lead session passes you that data. The left-edge swipe home stays; clashes are handled if they
happen.

Build (after the founder approves your plan):
1. Recognise the scribble over a Sidekick's WKWebView without breaking taps, scrolls and the
   Sidekick's own gestures (Reminders pulls up and down between lists). Tune on the founder's
   samples; add a test with them.
2. Freeze the current Sidekick view (WKWebView snapshot) into a full-screen drawing layer that
   does not look like a screenshot (no screenshot chrome). Pen; arrows and circles are just
   strokes. Undo, cancel, send. Words on screen per `docs/WRITING.md` (wording mockup first).
3. Speech for the whole session, transcribed on the device (`SFSpeechRecognizer` with
   `requiresOnDeviceRecognition`, or iOS 26 SpeechAnalyzer; say which and the iOS target). Audio
   never leaves the phone. Keep word timings and stroke timings (enhancement 1 needs them later).
4. Send to `POST /repairs` (see contract); queue it if offline. No report back to the user.
5. Tests: the recogniser accepts the founder's samples and rejects ordinary scrolls and swipes;
   the payload has transcript, strokes, screenshot and drawing; audio is never in it.

Owns: new Swift files under `shell/Midas/` and `shell/MidasTests/`, `shell/project.yml` only for
permission strings (microphone, speech) — tell the lead. Question for the plan: Info.plist
wording for the microphone and speech prompts.
