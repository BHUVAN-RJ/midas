# STAGING ONLY: test build branch, never merge to main

- This branch (`agent/test-build-35`) exists only to build a TestFlight test build.
- Build with the **Midas Test** scheme and `-configuration Test` (bundle `com.bhuvanrj.midas.test`,
  staging server). Never archive the "Midas" scheme or `-configuration Release` from here.
- Staging only: never deploy anything from this branch to live.
- Never merge this branch into `main`, never push it to `main`.
- Contents: main 93b110d (repair lanes W4/W5/W7 + staging guards). The earlier test on this
  branch was removed (founder, 2026-11-22).
- Build 42 = main 93b110d repair lanes, dictation removed (founder 2026-11-22). Next build above 42.
- TestFlight Midas Test reached build 42; the next TestFlight build must use a build number above 42.
- Build 43 = build 42 + repair instant send and vague-words setting rule (c253fee, founder 2026-11-22). Next build above 43.
- Build 44 = build 43 + answering a question card closes at once, session checks rewritten (1404495, founder 2026-11-22). Next build above 44.
- Build 45 = agent/repair-cancel-x 2bbb83d (main + Send closes at once + concrete question cards + cancel X + question opens by itself + card in Midas design), founder 2026-11-22. Branch agent/test-build-45. Next build above 45.
- Build 46 = build 45 + Editing tag cycles (agent/repair-tag-cycle be57b2f) + unclear code requests become a question (agent/repair-unclear-ask 668ca4b), founder 2026-11-23. Branch agent/test-build-46. Next build above 46.
