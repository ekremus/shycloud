# ShyCloud — Design Spec

**Date:** 2026-10-10 · **Revision:** 5 (deep pause 2026-10-11, stop uploads completely 2026-10-12, full stop by default and activation thaw 2026-10-12) · **Status:** Approved by owner (ekremus)
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

| Mode (id) | Menu label | Behaviour |
|---|---|---|
| `alwaysSync` | `Sync On` | Targets always running |
| `alwaysPause` | `Sync Off` | Targets always paused (vacation/sleep mode) |
| `scheduled` | `Scheduled (02:00–09:00)` | Running inside the window, paused outside. **Default.** |

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

Status line variants: `Syncing`, `Syncing · pauses at 09:00`, `Paused`, `Paused · syncs at 02:00`, `Can't pause: allow ShyCloud in Login Items` (watchdog agent disabled). The safety helper is invisible in the UI: while it is still starting, the line reads `Syncing` like any other syncing state. During a health-check cooldown (§4.1) the status is plain syncing: `Syncing · pauses at <cooldown end>` (or `Syncing` when the sync window opens first). A launch or activation thaw (§4.1) does not change the status.
Icon (SF Symbols, template rendering): running → `icloud`; paused → `icloud.slash`.

### 3.2 Quit
- **Quit ShyCloud** always resumes all targets and exits. No alert, no "Keep Paused": a frozen `bird` with nobody letting it breathe (§4.1) would hang any app that makes a synchronous call to it.
- Every other termination path (logout, shutdown, restart, Sparkle relaunch, `SIGTERM`) resumes all targets too (`applicationWillTerminate` + `NSWorkspace.willPowerOffNotification`).

### 3.3 Settings (single small window)
Implemented as an AppKit `NSWindow` hosting the SwiftUI `SettingsView` (`SettingsWindowController.shared.show()`), so it can be opened from the menu and from `applicationShouldHandleReopen` alike; `show()` deminiaturizes if needed, activates the app forcefully (`NSRunningApplication.current.activate(options: [.activateAllWindows])`), then `makeKeyAndOrderFront` + `orderFrontRegardless` so an already-open window comes to front for an accessory app.

Contents (grouped `Form`, five sections, no toggle for iCloud Drive: it is not a user choice, the schedule decides it):
- **Status header** (first section, no title; read-only, updates live from `sync.status`, which is `@Observable`): an `HStack` with SF Symbol `icloud` (syncing, tinted accent color) or `icloud.slash` (paused, tinted `.secondary`) at ~28 pt with `.symbolRenderingMode(.hierarchical)`, next to a headline and a secondary subtitle; the row is one accessibility element (`.accessibilityElement(children: .combine)`). Strings come from `StatusText.settingsHeadline(_:)` / `settingsDetail(_:)`:
  - `paused(until: d)`: "iCloud Drive is paused" / "Syncs at <time>"
  - `paused(nil)`: "iCloud Drive is paused" / "Until you choose Sync On or Scheduled"
  - `syncing(until: d)`: "iCloud Drive is syncing" / "Pauses at <time>"
  - `syncing(nil)`, `waitingForHelper`: "iCloud Drive is syncing" / "Sync is on"
  - `helperDisabled`: "iCloud Drive can't be paused" / "Allow ShyCloud in System Settings › Login Items"
- **Pause strength** (second section, no title, right under the status header because it changes what "paused" means for every target):
  - ☐ Let apps reach iCloud while paused (stored as `!stopUploadsCompletely`, so off by default). Subtitle: "Breathing mode. Apps never wait, but uploads keep going in the background." ON switches the full stop to breathing (§4.1).
- **Sync hours:** Start time, End time (`DatePicker` with `.hourAndMinute`). Footer: "iCloud Drive syncs only during these hours and stays paused the rest of the day." plus the inline error "Start and end can't be the same time." when equal.
- **Also pause** (ON means it is paused along with iCloud Drive outside sync hours). Each explanation is a subtitle inside its toggle's row (second `Text` in the `Toggle` label), never a separate row; toggles are labelled by the thing, not "Pause X":
  - ☐ iCloud Photos. Subtitle: "Stops photo and video uploads and downloads. The Photos app still opens."
  - ☐ Photo analysis. Subtitle: "Low risk. Photos still opens normally."
  - ☐ CloudKit. Subtitle: "Also pauses Messages, Notes, Reminders and other iCloud apps. They may freeze until sync resumes."
  - Section footer: "While paused, files stored only in iCloud (cloud icon in Finder) open after sync resumes."
- **General:**
  - Open at login (`SMAppService.mainApp`; if `.requiresApproval` the toggle subtitle reads "Needs approval in System Settings." and a button → `SMAppService.openSystemSettingsLoginItems()`)
  - Show in menu bar (when off, subtitle: "Open ShyCloud again from Applications to return here.")
  - Automatically check for updates (Sparkle `automaticallyChecksForUpdates`) + "Check for Updates…" button
- No safety helper section: the helper is invisible in the UI (it is still registered and still gates pausing, §4). If it is disabled, only the menu status line says so (§3.1).
- The window has a fixed size (`.frame(width: 440, height: …)` on the Form, sized so the content normally fits without scrolling); the grouped Form scrolls if needed. Never let SwiftUI content and the window size each other.
- No "Acknowledgements" button in Settings; third-party licenses live in About (§3.4).

### 3.4 About
Custom SwiftUI `AboutView` in one reusable `NSWindow` (`AboutWindowController.shared.show()`, brought to front like Settings, §3.3). Fixed size 300×360, `.titled, .closable, .fullSizeContentView`, transparent titlebar with hidden title, movable by background, closes with ⌘W or Esc, default window background (light/dark automatic). Centered content: app icon (96 pt), "ShyCloud", "Version X (build Y)" (selectable), "Pause iCloud Drive sync on a schedule.", link buttons "GitHub" (repository) and "Third-Party Licenses" (file URL of the bundled `THIRD_PARTY_NOTICES.txt`, which includes Sparkle's MIT notice), footnote "Free and open source · GPL-3.0". No Apple trademark line inside the app.

### 3.5 First launch
No onboarding. Defaults: mode `scheduled`, window 02:00–09:00, open-at-login registered, watchdog registered, menu icon shown. Note: 02:00 does not exist on spring-forward days in some time zones; schedule math handles it (§4).

### 3.6 Hidden icon
When "Show in menu bar" is off (or the user hides it in System Settings › Menu Bar), launching the app again triggers `applicationShouldHandleReopen` (via `@NSApplicationDelegateAdaptor`), which opens the Settings window. A reopen also sets nothing else.

## 4. Architecture

Single app target + one embedded LaunchAgent helper (both arm64). Units, each with one job:

| Unit | Responsibility |
|---|---|
| `Schedule` (pure value type) | `init(start: DateComponents, end: DateComponents)`; `isInside(_ date: Date, calendar: Calendar) -> Bool`; `nextChange(after: Date, calendar: Calendar) -> Date`. Uses `calendar.nextDate(after:matching:matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)` so DST gaps/repeats behave. |
| `PauseTarget` (enum) | `.cloudKit`, `.drive`, `.photos`, `.photoAnalysis`. Each has display name, risk text, and an **allowlist of absolute executable paths**: `bird` → `/System/Library/PrivateFrameworks/iCloudDriveCore.framework/Versions/A/Support/bird` (verified on 27.0.1) and `/System/Library/PrivateFrameworks/CloudDocsDaemon.framework/Versions/A/Support/bird` (older layout); `cloudd` → `/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Support/cloudd`; `cloudphotod` → `/System/Library/PrivateFrameworks/CloudPhotoLibrary.framework/Versions/A/Support/cloudphotod` (verified on macOS 27); `photoanalysisd` → `/System/Library/PrivateFrameworks/PhotoAnalysis.framework/Versions/A/Support/photoanalysisd`. **Never match by name.** (This Mac runs Simulator copies of cloudd/photoanalysisd as the same uid under `/Library/Developer/CoreSimulator/...` — they must never be touched.) Pause order: drive, photos, photoAnalysis, cloudKit; resume order: reverse. |
| `ProcessInspector` (protocol) + `DarwinProcessInspector` | `pids(for target) -> [ProcessID]`: `proc_listallpids` → for each pid, `proc_pidpath` equals an allowlisted path **and** owner uid (`proc_pidinfo PROC_PIDTBSDINFO pbi_uid`) == `getuid()`. `isStopped(pid) -> Bool`: `pbi_status == SSTOP`. `startTime(pid)` for identity. |
| `ProcessController` (protocol) + `SignalProcessController` | `pause(_ targets:)`, `resume(_ targets:)`, `resumeAll()`, and for breathing `releaseForBreath()` / `restopAfterBreath()` (SIGCONT/SIGSTOP only the processes it paused, no process-table scan, same pause/resume order). Re-verifies path+uid+start time immediately before each `kill(pid, SIGSTOP/SIGCONT)`. Watches each paused pid with a `DispatchSource.makeProcessSource(.exit)`; on exit it asks `SyncController` to re-apply (catches respawn instantly). This is the only unit that touches other processes. |
| `Breather` | Deep pause cycle (§4.1): while running, every `breathInterval` = 2.0 s it releases the paused targets for `breathDuration` = 0.2 s, then stops them again. Driven by an injectable `OneShotTimer` (`DispatchOneShotTimer`: one `DispatchSourceTimer` on main, 20 ms leeway). |
| `ResponsivenessProbe` (protocol) + `UbiquityProbe` | `ping(answered:)`: calls `FileManager.default.ubiquityIdentityToken` on a background queue and reports back on main when it returns (never, if `bird` hangs). |
| `Settings` | UserDefaults-backed: mode, start, end, enabled optional targets, `stopUploadsCompletely` (key `stopUploadsCompletely`, default true; users who never set the key get true), showInMenuBar, lastSyncedAt. Validation. `onChange` fires for mode, schedule, targets and `stopUploadsCompletely`. |
| `SafetyFiles` | Paths under `~/Library/Application Support/ShyCloud/`: `heartbeat` (Unix timestamp text, written every 30 s) and `watchdog-ran` (written by each watchdog run). |
| `SyncController` (`@MainActor @Observable`) | Combines mode + schedule into desired state; applies via `ProcessController` (idempotently, every time); pausing means a full stop, or breathing when the user opts in (§4.1). Re-applies on: settings change, wake (`NSWorkspace.shared.notificationCenter` `.didWakeNotification`), `.NSSystemClockDidChange`, `.NSSystemTimeZoneDidChange`, `.NSCalendarDayChanged` (all on `NotificationCenter.default`), process exit events, and a 30 s tick that also writes the heartbeat and runs the health check (state changes therefore take effect within ≤ 30 s of a window boundary). `handleAppLaunch()` on `.willLaunchApplicationNotification` / `.didLaunchApplicationNotification` and `handleAppActivation(bundleID:)` on `.didActivateApplicationNotification` (workspace center; an app without a bundle id is keyed by `pid <n>`). Resumes all and stops breathing on `.willSleepNotification`, `.willPowerOffNotification` (workspace center) and quit. While anything is paused holds `ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason:)` so App Nap can't stall the heartbeat or the breaths. Refuses to pause if watchdog status ≠ `.enabled`. |
| `ShyCloudWatchdog` (tiny CLI target) | Plist at `Contents/Library/LaunchAgents/com.ekremus.ShyCloud.Watchdog.plist` with `BundleProgram` = `Contents/MacOS/ShyCloudWatchdog`, `StartInterval` 60, registered via `SMAppService.agent(plistName:)` on every launch regardless of "Open at login". Each run: write `watchdog-ran`; if heartbeat ≤ 120 s old → exit; else SIGCONT every allowlisted target process of this uid → exit. Covers a crash at any moment, including mid-breath. Worst-case recovery ≈ 3 min. |
| UI | `ShyCloudApp` (scenes), `MenuContent`, `SettingsView`, `AboutView`, `AppDelegate` (reopen, terminate). |

### 4.1 Pause method: full stop (default) or breathing

Measured on macOS 27 (60 s runs): SIGSTOP on `bird` makes any app that does a synchronous XPC call to it hang for as long as it stays stopped, e.g. `FileManager.default.ubiquityIdentityToken`, which Chromium/CEF apps (GeForce NOW, Steam) call at launch. Alternatives measured: background QoS (`PRIO_DARWIN_BG`) also hangs when `bird` has a backlog (no priority donation); `nice` never pauses sync. **Breathing** measured 1.0–1.8 s per call and about 18 % of normal `bird` work, but it does not stop uploads (see Full stop). Since 2026-10-12 the default is **full stop** (`stopUploadsCompletely` = true); breathing is the opt-in "Let apps reach iCloud while paused".

- **Breathing (opt-in):** while paused, targets are stopped, and every 2.0 s (release to release) all paused targets run for 0.2 s, then are stopped again (`Breather`). In this mode targets are never left stopped without the breather running; every way out (`resumeEverything`) stops the breather first.
- **Launch thaw:** on every app launch notification, all targets run for `launchThawDuration` = 10 s (another launch extends it), then go back to paused + breathing. Event-driven, no polling. The status stays "paused".
- **Activation thaw:** when Finder (`com.apple.finder`) comes to the front (`didActivateApplicationNotification`) while paused; every other app, and shyCloud itself, is ignored, because thawing for any app leaked about 1.8 GB of uploads in 15 minutes of normal switching, targets run for `activationThawDuration` = 10 s through the same thaw timer (a running launch or activation thaw is extended to 10 s from now), then go back to paused. Finder thaws at most once per `activationDebounce` = 60 s, measured from its last thaw on a monotonic clock (`ProcessInfo.systemUptime`, injectable), so switching back and forth does not keep iCloud thawed; activations it ignores do not push the window back. Ignored while not paused (syncing, cooldown, helper not ready), asleep or quitting, and then nothing is recorded. Works the same in full stop and breathing. Logged with the `Sync` logger: `activation thaw: <bundle id>`, `activation thaw started` / `launch thaw started` when a new thaw begins, `thaw ended`.
- **Health check:** on every 30 s tick while paused and breathing, `UbiquityProbe` must answer within `probeTimeout` = 3.0 s (longer than the 2 s breath interval). At most one call is in flight: while the previous call has not returned, no new one starts. On timeout ShyCloud resumes everything and pauses nothing for `cooldownDuration` = 10 min (status: syncing), then tries again. `scripts/ubiquity-probe.swift` runs the same call from Terminal.
- **Full stop (default; `stopUploadsCompletely` = true, i.e. "Let apps reach iCloud while paused" off):** measured: during breaths `bird` hands uploads to `nsurlsessiond`, so a new 2 GB file still uploads under breathing, while a full freeze uploaded 0 MB. In full stop, paused targets (iCloud Drive and any enabled optional target) are stopped without breathing until a launch or Finder activation thaw, a resume or Sync On. Switching to full stop mid-breath stops the released targets again at once. The launch and activation thaws are unchanged, so launching apps and Finder coming to the front still reach iCloud. Apps that ask `bird` something while no thaw runs (Open/Save panels on iCloud folders, Chromium apps that ask after their thaw ended) wait until it runs. The health check is skipped in this mode because such a hang is expected by design, and a timeout would otherwise start a false cooldown that lets uploads run; a probe already in flight when full stop turns on cannot start a cooldown either (the timeout only counts while breathing). Every other safety rule (§5) is unchanged. `SyncController` logs `stop uploads completely: on/off`, `pause started: breathing|full stop` and `pause switched to …` with the `Sync` logger.
- **Energy:** breath and thaw timers use leeway; nothing polls faster than the breath; breaths signal only already-paused processes (no process-table scan).

## 5. Safety rules (must hold)

1. **Launch order:** write heartbeat → resume all allowlisted targets → register watchdog → apply desired state.
2. Resume all (and stop breathing) on sleep, power-off/logout, and every termination including Quit.
3. Only signal processes whose executable path is in the allowlist and whose uid == `getuid()`. Never match by name.
4. Re-verify path+uid right before every signal (PID reuse).
5. Watchdog resumes targets if the heartbeat is stale.
6. Unticking a target in Settings resumes it immediately.
7. If the watchdog is not enabled, ShyCloud never pauses and says so.
8. No root, no privileged helper, no private frameworks, no network except Sparkle.
9. In full stop (the default, §4.1) targets do not breathe; apps may wait until the next thaw or Sync On, and the health check is skipped. In breathing mode ("Let apps reach iCloud while paused") a stopped target always breathes; apps must never hang on iCloud for longer than about 2 s, and if the health check says they do, stop pausing for 10 min.

## 6. Build & tech

- XcodeGen `project.yml` → `ShyCloud.xcodeproj` (generated file committed for contributors without XcodeGen).
- Xcode 27, Swift 6 language mode, strict concurrency complete, SwiftUI, `LSUIElement = YES`.
- `ARCHS = arm64`, `MACOSX_DEPLOYMENT_TARGET = 26.0`.
- App Sandbox off (required to signal other processes). Hardened Runtime on.
- Only dependency: Sparkle 2 (SPM). Ship its license notice via the About "Third-Party Licenses" link.
- Bundle ids: `com.ekremus.ShyCloud`, `com.ekremus.ShyCloud.Watchdog`.

## 7. Testing

- **Unit (Swift Testing):** `Schedule` (inside/outside, midnight crossing, exact boundaries, DST spring-forward with start 02:00 in America/New_York, DST fall-back, time-zone change); `SyncController` with fake `ProcessController`/probe and a virtual clock driving fake timers (mode switching, settings changes, wake staying paused after a missed window, launch order, quit, refuse-to-pause when watchdog disabled, breathing rhythm, launch thaw and its extension, activation thaw (Finder only, other apps and shyCloud ignored, 60 s debounce on an injected clock, extends a running thaw, ignored when not paused, asleep or quitting, both full stop and breathing), health check timeout → cooldown, one probe in flight, full stop: default on, no breaths, launch thaw kept, no probe, no cooldown from an in-flight probe, switching on/off mid-breath, every resume rule still applies); `Breather` cycle; breath signals in `SignalProcessController`; watchdog decision logic as a pure function `WatchdogDecision.decide(heartbeat:now:) -> .exit | .resume`; `PauseTarget` path allowlist rejects `/Library/Developer/CoreSimulator/...` paths. Tests never signal real processes and never call the real probe.
- **Manual checklist (`docs/TESTING.md`)** on real processes: pause → `ps -o stat` shows `T` (briefly `S`/`R` while breathing); resume → `S`/`R`; Simulator `cloudd` untouched; Finder with a dataless file while paused; Chromium/CEF app launch and `scripts/ubiquity-probe.swift` while paused; git in an iCloud-synced repo while paused; sleep/wake; logout/login; force-quit → watchdog resumes within ~3 min; Quit resumes; hidden-icon reopen; login item approval flow; safety helper disabled warning.

## 8. Release & discoverability

- GitHub Actions: `swift test` + unsigned build on every push/PR.
- Release is a local script `scripts/release.sh` (no signing secrets in CI): archive, sign with Developer ID Application (**owner must create this certificate; only an Apple Development cert exists on this Mac, team LQJCF4Z633**), notarize (`notarytool`, keychain profile), staple, DMG (`hdiutil`), Sparkle EdDSA signature + `appcast.xml` committed to `docs/` (served by GitHub Pages), `gh release create`, regenerate the Homebrew cask.
- Homebrew cask in own tap `ekremus/homebrew-tap` first; submit to homebrew/cask once notability rules are met.
- README.md (English), first line: "Pause iCloud Drive sync on Mac, on a schedule." Sections: why (iCloud Drive slow / `bird` high CPU), how it works (SIGSTOP/SIGCONT and breathing explained honestly, allowlist, safety helper), install (DMG, brew), cloud-only file caveat, FAQ (why not App Store, is it safe, how to undo: quit or reboot), privacy, "Not affiliated with Apple. iCloud is a trademark of Apple Inc.". Screenshot + short GIF. README.tr.md linked at top.
- GitHub description + topics: `icloud`, `icloud-drive`, `macos`, `menu-bar-app`, `swift`, `swiftui`, `apple-silicon`, `sync-pause`, `productivity`.
- Files: LICENSE (GPL-3.0), CONTRIBUTING.md (inbound = MIT), SECURITY.md, CHANGELOG.md, THIRD_PARTY_NOTICES.md (Sparkle).

## 9. Out of scope (v1)

Spotlight pausing (runs as root), per-folder sync control, multiple windows / weekday rules, notifications, Intel Macs, macOS < 26, Mac App Store build (sandbox forbids signalling other processes).
