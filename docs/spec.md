# ShyCloud — Design Spec

**Date:** 2026-10-10 · **Status:** Approved by owner (ekremus)
**One-liner:** Pause iCloud Drive sync on Mac, on a schedule.
**Research:** see [research.md](research.md)

---

## 1. Product

A free, open-source macOS menu bar app that keeps iCloud Drive sync paused while you work and lets it run in a time window you choose (default 02:00–09:00).

- Name: **ShyCloud** (reads like "iCloud", avoids Apple's mark in the name).
- Repo: `github.com/ekremus/shycloud` · License: **GPL-3.0** (free forever; no closed-source resale). Contributors sign off a CLA-lite in CONTRIBUTING.md granting the owner relicensing rights (keeps a future App Store build possible).
- Platform: **Apple Silicon only (arm64), macOS 26+**.
- Languages: English (base) + Turkish, via String Catalog (`Localizable.xcstrings`).
- No notifications. No analytics. No network access except Sparkle update checks.

## 2. Modes

Exactly one mode is active, persisted across launches:

| Mode | Menu label | Behaviour |
|---|---|---|
| On | `On` | Targets always running |
| Off | `Off` | Targets always paused ("vacation/sleep mode") |
| Scheduled | `Scheduled (02:00–09:00)` | Running inside the window, paused outside. Default mode |

- Window = one daily start/end time, same every day. End < start means it crosses midnight. Start == end is invalid (Settings prevents it).
- There is no "sync now" override separate from modes: choosing **On** is the override.

## 3. UI

### 3.1 Menu bar item (classic `NSMenu` style via SwiftUI `MenuBarExtra` with `.menu` style)

```
ShyCloud — Paused · syncs at 02:00      (disabled status line)
─────────────────
  On
  Off
✓ Scheduled (02:00–09:00)
─────────────────
  Settings…        ⌘,
  About ShyCloud
  Quit ShyCloud    ⌘Q
```

Status line variants: `Syncing`, `Syncing · pauses at 09:00`, `Paused`, `Paused · syncs at 02:00`.
Icon (SF Symbols, template): running → `icloud`; paused → `icloud.slash`.

### 3.2 Quit
Quit shows an alert: "Keep iCloud paused after quitting?" with buttons **Resume iCloud** (default) and **Keep Paused**, plus informational text: "iCloud resumes automatically when you restart or log out." If currently running, quit without asking.
"Keep Paused" disables the watchdog for this session (writes a flag it reads) and exits without resuming.

### 3.3 Settings (small panel window, single page, `Settings` scene)
- **Sync window:** Start time, End time (hour+minute pickers).
- **What to pause:**
  - ☑ iCloud Drive (`bird`) — always on, disabled checkbox
  - ☐ Photo analysis (`photoanalysisd`)
  - ☐ CloudKit (`cloudd`) — under "Advanced", with warning: "Also pauses Messages, Notes, Reminders and other apps that sync with iCloud."
  - Link: "Pause iCloud Photos in the Photos app…" (opens Photos)
- **General:**
  - Open at login (SMAppService; show "Needs approval in System Settings" + button if `.requiresApproval`)
  - Show in menu bar (when off: explain "Open ShyCloud again from Applications to see this window.")
  - Automatically check for updates (Sparkle)
- Footer note: "While paused, files stored only in iCloud (cloud icon in Finder) can't open until sync runs."

### 3.4 About
Standard About panel: icon, version, "Not affiliated with Apple. iCloud is a trademark of Apple Inc.", GitHub link, license.

### 3.5 First launch
No onboarding window. Default mode Scheduled 02:00–09:00, open-at-login registered, menu icon shown.

### 3.6 Hidden icon
When "Show in menu bar" is off (or the user hid it via System Settings › Menu Bar), launching the app again (`applicationShouldHandleReopen`) opens Settings.

## 4. Architecture

Single app target + one embedded LaunchAgent helper. Units, each with one job:

| Unit | Responsibility | Depends on |
|---|---|---|
| `Schedule` (pure) | Given window + `Date` + `Calendar` → `shouldRun: Bool`, `nextChange: Date` | nothing |
| `PauseTarget` (enum) | `drive(bird)`, `photoAnalysis(photoanalysisd)`, `cloudKit(cloudd)` — process name, display name, risk | nothing |
| `ProcessController` (protocol) | `pause(_ targets)`, `resume(_ targets)`, `isPaused(target)` | — |
| `SignalProcessController` | Real impl: finds PIDs of the current user's processes by exact executable path/name (`proc_listallpids` + `proc_pidpath`, uid match), sends SIGSTOP/SIGCONT, re-verifies PID identity immediately before signalling | Darwin |
| `SyncController` (@MainActor, @Observable) | Holds mode + settings, computes desired state, applies it via `ProcessController`, schedules a timer for `nextChange`, re-applies on: settings change, wake (`NSWorkspace.didWakeNotification`), clock/time-zone change (`NSSystemClockDidChange`, `NSSystemTimeZoneDidChange`), and a 60 s safety tick (catches respawned `bird` with a new PID) | Schedule, ProcessController, Settings |
| `Settings` | `@AppStorage`/UserDefaults keys, validation | — |
| `Heartbeat` | Writes timestamp to `~/Library/Application Support/ShyCloud/heartbeat` every 30 s; writes `keep-paused` flag on "Keep Paused" quit | — |
| `ShyCloudWatchdog` (LaunchAgent, tiny CLI) | Registered via `SMAppService.agent(plistName:)`, `StartInterval 60`. If heartbeat older than 120 s and no `keep-paused` flag → SIGCONT all known targets; then exits | Darwin |
| UI | `MenuBarExtra`, `SettingsView`, About, quit alert | SyncController |

`ProcessController` is the only place that touches other processes, so a future official API (or a sandboxed App Store variant) swaps only this unit.

## 5. Safety rules (must hold)

1. On launch: resume all targets once, then apply desired state.
2. On sleep (`willSleepNotification`), power-off/logout (`NSWorkspace.willPowerOffNotification`), and normal termination: resume all targets — except Quit + "Keep Paused".
3. Only signal processes owned by the current uid whose executable path matches the known system path. Never signal anything else.
4. Re-verify PID → path right before every signal (PID reuse).
5. Watchdog resumes targets if the app stops heartbeating (crash, force quit).
6. Untick a target in Settings → resume it immediately.
7. No root, no helper tools with privileges, no private frameworks.

## 6. Build & tech

- Xcode project, Swift 6 language mode, strict concurrency, SwiftUI, `LSUIElement = YES`.
- `ARCHS = arm64`, deployment target macOS 26.0.
- Not sandboxed (required to signal other processes). Hardened Runtime on.
- Only dependency: Sparkle 2 (SPM), EdDSA-signed appcast hosted on GitHub Pages/Releases.
- Bundle id: `com.ekremus.ShyCloud`; helper: `com.ekremus.ShyCloud.Watchdog`.

## 7. Testing

- **Unit (Swift Testing):** `Schedule` (inside/outside window, crossing midnight, boundaries exactly at start/end, DST change days, time-zone change), `SyncController` with a fake `ProcessController` (mode switching, settings changes, wake, launch-resume, quit paths), `Settings` validation.
- **Manual checklist (docs/TESTING.md)** on real `bird`: pause/resume visible in `ps -o stat` (`T` state), Finder behaviour with a dataless file, sleep/wake, logout/login, force-quit → watchdog resumes within ~2 min, "Keep Paused" quit, hidden icon reopen, login item approval flow.

## 8. Release & discoverability

- GitHub Actions: build + test on PR; tag → archive, sign (Developer ID Application — **owner must create this certificate; none on this Mac yet**), notarize (`notarytool`), staple, create DMG, upload to Releases, update Sparkle appcast.
- Homebrew cask `shycloud` (own tap first: `ekremus/homebrew-tap`; submit to homebrew-cask once it meets notability rules).
- README (English), first line: "Pause iCloud Drive sync on Mac, on a schedule." Sections: why (iCloud Drive slow / `bird` high CPU), how it works (SIGSTOP/SIGCONT, honestly explained), install (DMG, brew), cloud-only file caveat, FAQ (why not App Store, is it safe, how to undo), privacy (no data collected), "Not affiliated with Apple" line. Screenshot + short GIF.
- GitHub description + topics: `icloud`, `icloud-drive`, `macos`, `menu-bar-app`, `swift`, `swiftui`, `apple-silicon`, `sync-pause`, `productivity`.
- `README.tr.md` Turkish version linked from top.
- Files: LICENSE (GPL-3.0), CONTRIBUTING.md (sign-off + relicense grant), SECURITY.md, CHANGELOG.md.

## 9. Out of scope (v1)

Spotlight pausing (needs root), per-folder sync control, multiple windows / weekday rules, notifications, Intel Macs, macOS < 26, Mac App Store build.
