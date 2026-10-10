# ShyCloud — Research Notes (2026-10-10)

Tagline: **Pause iCloud Drive sync on a schedule.** Free, open source, Apple Silicon, macOS menu bar app.

## Why
iCloud Drive sync (`bird`) causes stalls during work: I/O contention, Finder "needs to be downloaded" errors, git/Xcode trouble in synced folders. Users want sync to run only at night.

## Competitors (none does exactly this)
| Tool | Gap |
|---|---|
| [Failsno/icloud-pause](https://github.com/Failsno/icloud-pause) | SwiftBar plugin, SIGSTOP bird+cloudd for 4/8/12/24h. No daily schedule, no vacation mode, needs SwiftBar |
| [viktor-svirsky/hotspot-mode](https://github.com/viktor-svirsky/hotspot-mode) | SwiftBar manual toggle only |
| [Offloader](https://offloader.io/offloader) | Paid; offloads files, does not pause sync |
| [ori0o0p/icloud-sync-trigger](https://github.com/ori0o0p/icloud-sync-trigger) | Forces sync (opposite) |

## Name
"ShyCloud" — reads like "iCloud", avoids Apple trademark in the app name (Apple discourages its marks in app names). GitHub name collisions: 1. Use "iCloud" descriptively only, plus "Not affiliated with Apple. iCloud is a trademark of Apple Inc."

SEO phrases: pause iCloud sync mac · schedule iCloud Drive sync · stop iCloud syncing mac · iCloud Drive slow / bird high CPU · Apple Silicon menu bar app.
GitHub topics: icloud, icloud-drive, macos, menu-bar-app, swift, swiftui, apple-silicon, sync-pause.

## Technical findings (verified on macOS 27.0.1 unless marked [web]/[inferred])
- Sync processes, all running as the user (no root): `bird`, `fileproviderd`, `iCloudDriveFileProvider.appex`, `cloudd`, `photoanalysisd`, `cloudphotod` (on demand). `mds` (Spotlight) runs as root → out of scope.
- **No public API** to pause iCloud Drive. `brctl` on macOS 27 has no pause/download/evict. NSFileProviderManager only controls your own provider.
- **Only working method:** SIGSTOP / SIGCONT on `bird`. `kill` doesn't work (launchd respawns); stopped process keeps its PID so it isn't respawned.
- Side effect: opening a dataless (cloud-only) file while paused hangs the opening app until resume. Local files are fine.
- Logout: launchd SIGKILLs stopped bird after 5s exit timeout → fresh bird next login (self-healing) [inferred].
- **App Sandbox blocks signalling other processes** [web, inferred] → Mac App Store not possible with this method. Ship via GitHub, Developer ID + notarization, Hardened Runtime. Keep the pause engine behind a protocol so a future official API could replace it.
- Always-resume guarantees: SIGCONT on quit, sleep, logout/power-off, and on every launch; verify PID is still `bird` via `proc_pidpath` before signalling; a small SMAppService LaunchAgent watchdog resumes if the app dies.
- Optional pause targets: `photoanalysisd` (low risk), `cloudphotod` (Photos has its own pause — prefer linking), `cloudd` (advanced, affects Messages/Notes/Keychain-adjacent CloudKit apps).
- UI: SwiftUI `MenuBarExtra(isInserted:)`, `LSUIElement`. Hidden icon → relaunching app triggers `applicationShouldHandleReopen` → show settings. macOS 26 lets users hide menu bar items in System Settings, so reopen path is required anyway.
- Login item: `SMAppService.mainApp.register()`; handle `.requiresApproval`.
