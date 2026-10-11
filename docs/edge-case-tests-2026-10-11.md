# Edge case and stress tests (2026-10-11)

Real Mac: MacBook Pro M4 Pro, macOS 27.0.1. Release build of shyCloud in /Applications. Each test sets the mode, relaunches the app and samples the `bird` process state every 50 ms. "Max frozen" is the longest time `bird` stayed stopped. An app "hang" is a `ubiquityIdentityToken` call that takes longer than 3 seconds.

## Edge cases (all passed)

| # | Scenario | Result |
|---|---|---|
| E1 | Breathing in Sync Off | Max frozen 1.86 s. `bird` runs between breaths. |
| E2 | 20 iCloud calls while paused | Worst 1.52 s. No hangs. |
| E3 | `bird` killed, new one started on demand | New `bird` paused after 3 s and breathing. |
| E4 | An app launches | `bird` ran freely for the 10 s thaw. Breathing came back after. |
| E5 | Support folder not writable (heartbeat fails) | No pausing at all. Pausing came back when the folder was writable again. |
| E6 | shyCloud opened a second time | The second copy quit itself. One instance kept working. |
| E7 | SIGTERM | `bird` running right after quit. |
| E8 | Broken settings (hour 99, unknown mode) | App runs with defaults. No crash. |
| E9 | Scheduled, inside the sync window | `bird` never stopped. |
| E10 | Photo analysis and CloudKit paused too | Worst iCloud call 1.53 s. No hangs. |
| E11 | shyCloud crashes while paused | Background helper turned iCloud back on after 120 s. |
| E12 | 20 minutes in Sync Off | Memory 17 MB at the end, no file handle growth, 1.6 s of CPU in total, no hangs. |

## Stress (all passed)

| # | Scenario | Result |
|---|---|---|
| S1 | 10 CPU-bound loops running | Max frozen 1.89 s, worst iCloud call 1.76 s. |
| S2 | 15 app launches in 30 s | Breathing normal afterwards. |
| S3 | `bird` killed 5 times in a row | New `bird` paused and breathing, no hangs. |
| S4 | Quit and relaunch shyCloud 10 times | `bird` running after every quit. |
| S5 | 300 files written to iCloud Drive while paused | All 300 uploaded 50 s after resume. Content identical. No duplicate files. |
| S6 | Clone, 20 branches, commits, merges, gc and fsck in a repo on iCloud Desktop while paused | 1 s, no errors. |
| S7 | Full Xcode build of a project on iCloud Desktop while paused | 15 s, success. |
| S8 | Coordinated write and read in iCloud Drive (what document apps and Open/Save panels do) | Worst 0.01 s. |
| S9 | Listing all of iCloud Drive (62,932 items) while paused | 2 s. |

No crash reports were created during any run.

## Found and fixed during testing

- A second copy of shyCloud could run next to the first. It now quits itself and shows Settings in the running one.
- After `bird` restarts, shyCloud now checks again at 2, 5 and 10 seconds instead of waiting up to 30 seconds.
- shyCloud now logs pause, resume and cooldown events (`log show --predicate 'subsystem == "com.ekremus.ShyCloud"'`).
- iCloud conflict copies (`ShyCloud 2.xcodeproj`, `Info 2.plist`) had been committed by mistake. They were removed and `.gitignore` now blocks them.

## Not tested yet

Sleep and wake, logging out, a cloud-only file opened while paused, and the app moved from a DMG. These need a person at the Mac or a signed DMG.
