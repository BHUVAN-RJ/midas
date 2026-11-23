# STAGING ONLY: test build branch, never merge to main

- This branch (`agent/test-build-35`) exists only to build a TestFlight test build.
- Build with the **Midas Test** scheme and `-configuration Test` (bundle `com.bhuvanrj.midas.test`,
  staging server). Never archive the "Midas" scheme or `-configuration Release` from here.
- Staging only: never deploy anything from this branch to live.
- Never merge this branch into `main`, never push it to `main`.
- Contents: main 93b110d (repair lanes W4/W5/W7 + staging guards). The earlier test on this
  branch was removed (founder, 2026-11-22).
- TestFlight Midas Test reached build 41; the next TestFlight build must use a build number above 41.
