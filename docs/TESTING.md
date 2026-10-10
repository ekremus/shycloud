# ShyCloud manual test checklist

Run on Apple Silicon, macOS 26 and macOS 27. Build: `xcodebuild -project ShyCloud.xcodeproj -scheme ShyCloud -configuration Debug -derivedDataPath /private/tmp/shycloud-dd build`, then copy `/private/tmp/shycloud-dd/Build/Products/Debug/ShyCloud.app` to `/Applications` (SMAppService needs a stable location).

**Always install from a clean build (`rm -rf /private/tmp/shycloud-dd` first); incremental builds can break the embedded watchdog's signature.**

Useful commands:
- State of targets: `ps -axo pid,stat,comm | grep -E "/(bird|cloudd|photoanalysisd)$"` (`T` = paused, `S`/`R` = running)
- Watchdog registered: `launchctl print gui/$(id -u)/com.ekremus.ShyCloud.Watchdog | head -5`
- Safety files: `ls -la ~/Library/Application\ Support/ShyCloud/`
- Emergency resume: `killall -CONT bird cloudd photoanalysisd`

| # | Scenario | Steps | Expected |
|---|---|---|---|
| 1 | First launch | Open app | Menu icon appears; mode Scheduled (02:00–09:00); watchdog registered; login item on |
| 2 | Pause | Choose "Sync Off" | `bird` shows `T` within 1 s; icon `icloud.slash`; status "Paused" |
| 3 | Resume | Choose "Sync On" | `bird` shows `S`/`R`; status "Syncing" |
| 4 | Schedule | Set window to start 2 min from now, mode Scheduled | Paused now; within 30 s after start time `bird` resumes; after end it pauses again |
| 5 | Simulator safety | Boot any iOS Simulator, choose Sync Off with CloudKit ticked | Only `/System/Library/...cloudd` is `T`; Simulator `cloudd` stays `S` |
| 6 | Optional targets | Tick Photo analysis, untick again | `photoanalysisd` `T`, then `S` immediately |
| 7 | Respawn | While paused: `kill -9 <bird pid>` | New `bird` pid appears and is `T` within a few seconds |
| 8 | Sleep/wake | Sync Off → sleep 1 min → wake | During sleep targets resumed; after wake the status may show "Starting safety helper…" for up to ~90 s (launchd skips the watchdog's runs during sleep), then pauses again |
| 9 | (removed) | Catch-up sync was removed (owner decision 2026-10-10); row number kept so others are not renumbered | n/a. Outside the window with Scheduled mode, nothing syncs even if `lastSyncedAt` is old |
| 10 | Quit, resume | Sync Off → Quit → Resume iCloud | `bird` `S`; no `keep-paused.json` |
| 11 | Quit, keep paused | Sync Off → Quit → Keep Paused, wait 3 min | `bird` stays `T`; `keep-paused.json` exists; watchdog does not resume |
| 12 | Keep-paused stale | After 11: `kill -9 <bird pid>` and wait ≤ 2 min | `keep-paused.json` deleted by watchdog; new `bird` running |
| 13 | Crash safety | Sync Off → `kill -9 <ShyCloud pid>` | Within ~3 min watchdog resumes `bird` |
| 14 | Relaunch after crash | Reopen app right after 13 | No flapping: `bird` paused, stays paused |
| 15 | Helper disabled | System Settings › Login Items & Extensions › disable ShyCloud in "Allow in the Background" | Status "Safety helper disabled — not pausing"; nothing paused; Settings shows warning |
| 16 | Hidden icon | Settings › untick Show in menu bar → close → open app from /Applications | Settings window appears |
| 17 | Logout | Sync Off → log out → log in | `bird` running fresh; ShyCloud relaunches and pauses again |
| 18 | Cloud-only file | Sync Off → open a Finder file with cloud icon | App waits; choosing Sync On lets it open |
| 19 | Turkish | System Settings › Language → Türkçe (or `defaults write com.ekremus.ShyCloud AppleLanguages '(tr)'`), relaunch | All menu/settings text Turkish |
| 20 | Update check | Settings › Check for Updates… | Sparkle dialog appears (feed may 404 before first release) |
| 21 | Watchdog dry run | Quit ShyCloud (Resume), run `/Applications/ShyCloud.app/Contents/MacOS/ShyCloudWatchdog; echo $?` | `0`; `bird` state `S`/`R`, never `T` |
| 22 | SIGTERM | Sync Off → `kill -TERM <ShyCloud pid>` | App quits and `bird` is `S`/`R` immediately (no 3-minute wait) |
| 23 | Moved app | First launch from the DMG, quit (Resume), copy to /Applications and launch from there, Sync Off, then `kill -9 <ShyCloud pid>` | Watchdog resumes `bird` within ~3 min (registration follows the new path) |
| 24 | Fresh install liveness | `rm ~/Library/Application\ Support/ShyCloud/watchdog-ran`, `defaults delete com.ekremus.ShyCloud watchdogRegisteredPath`, launch outside the window | Status shows "Starting safety helper…" (nothing paused) until the watchdog's first run, then pauses |
