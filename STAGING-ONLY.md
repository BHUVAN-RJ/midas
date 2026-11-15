# STAGING ONLY: test build branch, never merge to main

- This branch (`agent/test-build-35`) exists only to build a TestFlight test build.
- Build with the **Midas Test** scheme and `-configuration Test` (bundle `com.bhuvanrj.midas.test`,
  staging server). Never archive the "Midas" scheme or `-configuration Release` from here.
- Staging only: never deploy anything from this branch to live.
- Never merge this branch into `main`, never push it to `main`.
- Build 35 = dictation round 4 (`agent/dictation-test` @ b715957) + main 93b110d (repair lanes
  W4/W5/W7 + staging guards).
- Build 37 = build 35 + the keyboard (`agent/dictation-test` @ 8a3f079). 36 was left for the
  keyboard build archived from `agent/dictation-test`.
- The next TestFlight build must use a build number above 37.
