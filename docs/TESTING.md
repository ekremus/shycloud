# ShyCloud manual test checklist

Run on Apple Silicon, macOS 26 and macOS 27. Build: `xcodebuild -project ShyCloud.xcodeproj -scheme ShyCloud -configuration Debug -derivedDataPath /private/tmp/shycloud-dd build`, then copy `/private/tmp/shycloud-dd/Build/Products/Debug/ShyCloud.app` to `/Applications` (SMAppService needs a stable location).

**Always install from a clean build (`rm -rf /private/tmp/shycloud-dd` first); incremental builds can break the embedded watchdog's signature.**

Useful commands:
- State of targets: `ps -axo pid,stat,comm | grep -E "/(bird|cloudd|photoanalysisd)$"` (`T` = paused, `S`/`R` = running)
- Watchdog registered: `launchctl print gui/$(id -u)/com.ekremus.ShyCloud.Watchdog | head -5`
- Safety files: `ls -la ~/Library/Application\ Support/ShyCloud/`
- Emergency resume: `killall -CONT bird cloudd photoanalysisd`
- iCloud responsiveness: `swift scripts/ubiquity-probe.swift` (prints the latency of `FileManager.ubiquityIdentityToken`, or `HANG` and exits 1 after 3 s)

While paused, `bird` is breathing: `T` most of the time, `S`/`R` for 0.2 s every 2 s (deep pause, spec §4.1).

| # | Scenario | Steps | Expected |
|---|---|---|---|
| 1 | First launch | Open app | Menu icon appears; mode Scheduled (02:00–09:00); watchdog registered; login item on |
| 2 | Pause | Choose "Sync Off" | `bird` shows `T` within 1 s (briefly `S`/`R` while breathing); icon `icloud.slash`; status "Paused" |
| 3 | Resume | Choose "Sync On" | `bird` shows `S`/`R`; status "Syncing" |
| 4 | Schedule | Set window to start 2 min from now, mode Scheduled | Paused now; within 30 s after start time `bird` resumes; after end it pauses again |
| 5 | Simulator safety | Boot any iOS Simulator, choose Sync Off with CloudKit ticked | Only `/System/Library/...cloudd` is `T`; Simulator `cloudd` stays `S` |
| 6 | Optional targets | Tick Photo analysis, untick again | `photoanalysisd` `T`, then `S` immediately |
| 7 | Respawn | While paused: `kill -9 <bird pid>` | New `bird` pid appears and is `T` within a few seconds |
| 8 | Sleep/wake | Sync Off → sleep 1 min → wake | During sleep targets resumed; after wake the status may show "ShyCloud — Syncing" for up to ~90 s (launchd skips the watchdog's runs during sleep), then pauses again |
| 9 | (removed) | Catch-up sync was removed (owner decision 2026-10-10); row number kept so others are not renumbered | n/a. Outside the window with Scheduled mode, nothing syncs even if `lastSyncedAt` is old |
| 10 | Quit | Sync Off → Quit ShyCloud | No alert; app exits; `bird` `S`/`R` immediately |
| 11 | (removed) | "Keep Paused" was removed (deep pause, 2026-10-11) | n/a |
| 12 | (removed) | "Keep Paused" was removed (deep pause, 2026-10-11) | n/a |
| 13 | Crash safety | Sync Off → `kill -9 <ShyCloud pid>` | Within ~3 min watchdog resumes `bird` |
| 14 | Relaunch after crash | Reopen app right after 13 | No flapping: `bird` paused, stays paused |
| 15 | Helper disabled | System Settings › Login Items & Extensions › disable ShyCloud in "Allow in the Background" | Status "ShyCloud — Can't pause: allow ShyCloud in Login Items"; nothing paused |
| 16 | Hidden icon | Settings › untick Show in menu bar → close → open app from /Applications | Settings window appears |
| 17 | Logout | Sync Off → log out → log in | `bird` running fresh; ShyCloud relaunches and pauses again |
| 18 | Cloud-only file | Sync Off → open a Finder file with cloud icon | App waits; choosing Sync On lets it open |
| 20 | Update check | Settings › Check for Updates… | Sparkle dialog appears (feed may 404 before first release) |
| 21 | Watchdog dry run | Quit ShyCloud, run `/Applications/ShyCloud.app/Contents/MacOS/ShyCloudWatchdog; echo $?` | `0`; `bird` state `S`/`R`, never `T` |
| 22 | SIGTERM | Sync Off → `kill -TERM <ShyCloud pid>` | App quits and `bird` is `S`/`R` immediately (no 3-minute wait) |
| 23 | Moved app | First launch from the DMG, quit, copy to /Applications and launch from there, Sync Off, then `kill -9 <ShyCloud pid>` | Watchdog resumes `bird` within ~3 min (registration follows the new path) |
| 24 | Fresh install liveness | `rm ~/Library/Application\ Support/ShyCloud/watchdog-ran`, `defaults delete com.ekremus.ShyCloud watchdogRegisteredPath`, launch outside the window | Status shows "ShyCloud — Syncing" (nothing paused) until the watchdog's first run, then pauses |
| 25 | App launch while paused | Sync Off, wait 1 min, then launch GeForce NOW and Steam (Chromium/CEF apps) | Both open normally, no beachball; `bird` runs for ~10 s after each launch, then breathes again |
| 26 | Responsiveness while paused | Sync Off, wait 1 min, run `swift scripts/ubiquity-probe.swift` a few times | Every run prints a latency under 3 s; never `HANG` |
| 27 | Git while paused | Sync Off, in a git repo inside iCloud Drive (e.g. Desktop/Documents): `git status`, edit a file, `git commit` | Commands finish normally (no hang) |
