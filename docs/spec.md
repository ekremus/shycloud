# ShyCloud — Design Spec

**Date:** 2026-10-10 · **Revision:** 2 (after independent review) · **Status:** Approved by owner (ekremus)
**One-liner:** Pause iCloud Drive sync on Mac, on a schedule.
**Research:** see [research.md](research.md)

---

## 1. Product

A free, open-source macOS menu bar app that keeps iCloud Drive sync paused while you work and lets it run in a daily time window you choose (default 02:00–09:00).

- Name: **ShyCloud** (reads like "iCloud", avoids Apple's mark in the name).
- Repo: `github.com/ekremus/shycloud`.
- License: **GPL-3.0-or-later**. Anyone may use, modify and redistribute it free of charge; any redistributed version (including a modified or sold one) must ship its full source under the same license, so nobody can turn it into a closed product.
- Contributions: inbound contributions are accepted under the MIT license (stated in CONTRIBUTING.md and the PR template), which lets the owner relicense the whole codebase later if ever needed. (An App Store build is blocked anyway by the sandbox — see §9.)
- Platform: **Apple Silicon only (arm64), macOS 26+**.
- Languages: English (UI). README also in Turkish.
- No notifications. No analytics. No network access except Sparkle update checks.

## 2. Modes

Exactly one mode is active, persisted across launches.

| Mode (id) | Menu label EN / TR | Behaviour |
|---|---|---|
| `alwaysSync` | `Sync On` / `Senkron Açık` | Targets always running |
| `alwaysPause` | `Sync Off` / `Senkron Kapalı` | Targets always paused (vacation/sleep mode) |
| `scheduled` | `Scheduled (02:00–09:00)` / `Zamanlı (02:00–09:00)` | Running inside the window, paused outside. **Default.** |

- Window = one daily start and end time (hour + minute), same every day. End earlier than start means it crosses midnight. Start == end is invalid; Settings prevents it.
- Times are displayed in the user's locale format.
- Catch-up sync removed by owner decision 2026-10-10: sync never runs outside the window unless the user chooses Sync On. ShyCloud still records `lastSyncedAt` (set when targets have been running for ≥ 20 continuous minutes) for the "Last synced" menu line only.

## 3. UI

### 3.1 Menu bar item (classic menu: SwiftUI `MenuBarExtra(isInserted:)` with `.menuBarExtraStyle(.menu)`)

```
ShyCloud — Paused · syncs at 02:00        (disabled status line)
Last synced: today 08:59                  (disabled)
─────────────────
  Sync On
  Sync Off
✓ Scheduled (02:00–09:00)
─────────────────
  Settings…        ⌘,
  About ShyCloud
  Quit ShyCloud    ⌘Q
```

Status line variants: `Syncing`, `Syncing · pauses at 09:00`, `Paused`, `Paused · syncs at 02:00`, `Safety helper disabled — not pausing`.
Icon (SF Symbols, template rendering): running → `icloud`; paused → `icloud.slash`.

### 3.2 Quit
- Only the **Quit ShyCloud menu item** may ask. If iCloud is currently paused, it calls `NSApp.activate()` then shows an `NSAlert`: title "Keep iCloud paused after quitting?", info "iCloud resumes automatically when you restart or log out.", buttons **Resume iCloud** (default, Return) and **Keep Paused**.
- If iCloud is syncing, Quit exits immediately.
- Every other termination path (logout, shutdown, restart, Sparkle relaunch, `SIGTERM`) resumes all targets without asking (`applicationWillTerminate` + `NSWorkspace.willPowerOffNotification`).
- "Keep Paused" writes the keep-paused flag (§5) and exits without resuming.

### 3.3 Settings (single small window)
Implemented as an AppKit `NSWindow` hosting the SwiftUI `SettingsView` (`SettingsWindowController.shared.show()`), so it can be opened from the menu and from `applicationShouldHandleReopen` alike; always call `NSApp.activate()` first so it comes to front for an accessory app.

Contents:
- **Sync window:** Start time, End time (`DatePicker` with `.hourAndMinute`). Inline error when equal.
- **What to pause:**
  - ☑ iCloud Drive — always on, disabled checkbox
  - ☐ Photo analysis
  - ☐ CloudKit — under "Advanced", warning: "Also pauses Messages, Notes, Reminders and other apps that sync with iCloud. Those apps may freeze until sync resumes."
  - Link: "Pause iCloud Photos in the Photos app…" (opens Photos)
- **General:**
  - Open at login (`SMAppService.mainApp`; if `.requiresApproval` show "Needs approval" + button → `SMAppService.openSystemSettingsLoginItems()`)
  - Show in menu bar (when off: "Open ShyCloud again from Applications to return here.")
  - Automatically check for updates (Sparkle `automaticallyChecksForUpdates`) + "Check for Updates…" button
- **Safety helper status:** "Safety helper: On" or, if the watchdog agent status ≠ `.enabled`, a warning "Safety helper is disabled in System Settings › General › Login Items & Extensions. ShyCloud won't pause iCloud until it is enabled." + button.
- Footer: "While paused, files stored only in iCloud (cloud icon in Finder) can't open until sync runs."

### 3.4 About
`NSApp.orderFrontStandardAboutPanel` with credits: "Not affiliated with Apple. iCloud is a trademark of Apple Inc.", GitHub link, "GPL-3.0". Call `NSApp.activate()` first.

### 3.5 First launch
No onboarding. Defaults: mode `scheduled`, window 02:00–09:00, open-at-login registered, watchdog registered, menu icon shown. Note: 02:00 does not exist on spring-forward days in some time zones; schedule math handles it (§4).

### 3.6 Hidden icon
When "Show in menu bar" is off (or the user hides it in System Settings › Menu Bar), launching the app again triggers `applicationShouldHandleReopen` (via `@NSApplicationDelegateAdaptor`), which opens the Settings window. A reopen also sets nothing else.

## 4. Architecture

Single app target + one embedded LaunchAgent helper (both arm64). Units, each with one job:

| Unit | Responsibility |
|---|---|
| `Schedule` (pure value type) | `init(start: DateComponents, end: DateComponents)`; `isInside(_ date: Date, calendar: Calendar) -> Bool`; `nextChange(after: Date, calendar: Calendar) -> Date`. Uses `calendar.nextDate(after:matching:matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)` so DST gaps/repeats behave. |
| `PauseTarget` (enum) | `.cloudKit`, `.drive`, `.photoAnalysis`. Each has display name, risk text, and an **allowlist of absolute executable paths**: `bird` → `/System/Library/PrivateFrameworks/iCloudDriveCore.framework/Versions/A/Support/bird` (verified on 27.0.1) and `/System/Library/PrivateFrameworks/CloudDocsDaemon.framework/Versions/A/Support/bird` (older layout); `cloudd` → `/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Support/cloudd`; `photoanalysisd` → `/System/Library/PrivateFrameworks/PhotoAnalysis.framework/Versions/A/Support/photoanalysisd`. **Never match by name.** (This Mac runs Simulator copies of cloudd/photoanalysisd as the same uid under `/Library/Developer/CoreSimulator/...` — they must never be touched.) Pause order: drive, photoAnalysis, cloudKit; resume order: reverse. |
| `ProcessInspector` (protocol) + `DarwinProcessInspector` | `pids(for target) -> [ProcessID]`: `proc_listallpids` → for each pid, `proc_pidpath` equals an allowlisted path **and** owner uid (`proc_pidinfo PROC_PIDTBSDINFO pbi_uid`) == `getuid()`. `isStopped(pid) -> Bool`: `pbi_status == SSTOP`. `startTime(pid)` for identity. |
| `ProcessController` (protocol) + `SignalProcessController` | `pause(_ targets:)`, `resume(_ targets:)`, `resumeAll()`. Re-verifies path+uid immediately before each `kill(pid, SIGSTOP/SIGCONT)`. Returns the set of `(pid, startTime)` it stopped. Watches each paused pid with a `DispatchSource.makeProcessSource(.exit)`; on exit it asks `SyncController` to re-apply (catches respawn instantly). This is the only unit that touches other processes. |
| `Settings` | UserDefaults-backed: mode, start, end, enabled optional targets, showInMenuBar, lastSyncWindowCompletedAt. Validation. |
| `SafetyFiles` | Paths under `~/Library/Application Support/ShyCloud/`: `heartbeat` (Unix timestamp text, written every 30 s) and `keep-paused.json` (list of `{pid, startTime}`). |
| `SyncController` (`@MainActor @Observable`) | Combines mode + schedule into desired state; applies via `ProcessController` (idempotently, every time); re-applies on: settings change, wake (`NSWorkspace.shared.notificationCenter` `.didWakeNotification`), `.NSSystemClockDidChange`, `.NSSystemTimeZoneDidChange`, `.NSCalendarDayChanged` (all on `NotificationCenter.default`), process exit events, and a 30 s tick that also writes the heartbeat (state changes therefore take effect within ≤ 30 s of a window boundary). Resumes all on `.willSleepNotification` and `.willPowerOffNotification` (workspace center). While anything is paused holds `ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason:)` so App Nap can't stall the heartbeat. Refuses to pause if watchdog status ≠ `.enabled`. |
| `ShyCloudWatchdog` (tiny CLI target) | Plist at `Contents/Library/LaunchAgents/com.ekremus.ShyCloud.Watchdog.plist` with `BundleProgram` = `Contents/MacOS/ShyCloudWatchdog`, `StartInterval` 60, registered via `SMAppService.agent(plistName:)` on every launch regardless of "Open at login". Each run: if heartbeat ≤ 120 s old → exit. Else if `keep-paused.json` exists and every listed `{pid, startTime}` is still alive and stopped → exit. Else delete `keep-paused.json` and SIGCONT every allowlisted target process of this uid → exit. Worst-case recovery ≈ 3 min. |
| UI | `ShyCloudApp` (scenes), `MenuContent`, `SettingsView`, quit alert, `AppDelegate` (reopen, terminate). |

## 5. Safety rules (must hold)

1. **Launch order:** delete `keep-paused.json` → write heartbeat → resume all allowlisted targets → register watchdog → apply desired state.
2. Resume all on sleep, power-off/logout, and every termination except Quit + "Keep Paused".
3. Only signal processes whose executable path is in the allowlist and whose uid == `getuid()`. Never match by name.
4. Re-verify path+uid right before every signal (PID reuse).
5. Watchdog resumes targets if the heartbeat is stale, unless a valid keep-paused record matches still-stopped processes (a stale record is deleted).
6. Unticking a target in Settings resumes it immediately.
7. If the watchdog is not enabled, ShyCloud never pauses and says so.
8. No root, no privileged helper, no private frameworks, no network except Sparkle.

## 6. Build & tech

- XcodeGen `project.yml` → `ShyCloud.xcodeproj` (generated file committed for contributors without XcodeGen).
- Xcode 27, Swift 6 language mode, strict concurrency complete, SwiftUI, `LSUIElement = YES`.
- `ARCHS = arm64`, `MACOSX_DEPLOYMENT_TARGET = 26.0`.
- App Sandbox off (required to signal other processes). Hardened Runtime on.
- Only dependency: Sparkle 2 (SPM). Ship its license notice in About/Acknowledgements.
- Bundle ids: `com.ekremus.ShyCloud`, `com.ekremus.ShyCloud.Watchdog`.

## 7. Testing

- **Unit (Swift Testing):** `Schedule` (inside/outside, midnight crossing, exact boundaries, DST spring-forward with start 02:00 in America/New_York, DST fall-back, time-zone change); `SyncController` with fake `ProcessController`/inspector/clock (mode switching, settings changes, wake staying paused after a missed window, launch order, quit paths, refuse-to-pause when watchdog disabled); watchdog decision logic as a pure function `WatchdogDecision.decide(heartbeatAge:keepPaused:liveStopped:) -> .exit | .resume`; `PauseTarget` path allowlist rejects `/Library/Developer/CoreSimulator/...` paths.
- **Manual checklist (`docs/TESTING.md`)** on real processes: pause → `ps -o stat` shows `T`; resume → `S`/`R`; Simulator `cloudd` untouched; Finder with a dataless file while paused; sleep/wake; logout/login; force-quit → watchdog resumes within ~3 min; Quit + Keep Paused survives watchdog; Quit + Resume; hidden-icon reopen; login item approval flow; safety helper disabled warning.

## 8. Release & discoverability

- GitHub Actions: `swift test` + unsigned build on every push/PR.
- Release is a local script `scripts/release.sh` (no signing secrets in CI): archive, sign with Developer ID Application (**owner must create this certificate; only an Apple Development cert exists on this Mac, team LQJCF4Z633**), notarize (`notarytool`, keychain profile), staple, DMG (`hdiutil`), Sparkle EdDSA signature + `appcast.xml` committed to `docs/` (served by GitHub Pages), `gh release create`, regenerate the Homebrew cask.
- Homebrew cask in own tap `ekremus/homebrew-tap` first; submit to homebrew/cask once notability rules are met.
- README.md (English), first line: "Pause iCloud Drive sync on Mac, on a schedule." Sections: why (iCloud Drive slow / `bird` high CPU), how it works (SIGSTOP/SIGCONT explained honestly, allowlist, safety helper), install (DMG, brew), cloud-only file caveat, FAQ (why not App Store, is it safe, how to undo: quit or reboot), privacy, "Not affiliated with Apple. iCloud is a trademark of Apple Inc.". Screenshot + short GIF. README.tr.md linked at top.
- GitHub description + topics: `icloud`, `icloud-drive`, `macos`, `menu-bar-app`, `swift`, `swiftui`, `apple-silicon`, `sync-pause`, `productivity`.
- Files: LICENSE (GPL-3.0), CONTRIBUTING.md (inbound = MIT), SECURITY.md, CHANGELOG.md, THIRD_PARTY_NOTICES.md (Sparkle).

## 9. Out of scope (v1)

Spotlight pausing (runs as root), per-folder sync control, multiple windows / weekday rules, notifications, Intel Macs, macOS < 26, Mac App Store build (sandbox forbids signalling other processes).
