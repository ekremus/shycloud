# Pause method study — 2026-10-11

> **Correction (later the same day):** the traffic numbers below count only `cloudd`. Uploads of iCloud Drive files run through `nsurlsessiond`. A follow-up test with a new 30 MB file showed it uploaded within 5 minutes in Normal, Deep pause and Deep pause with CloudKit paused. Only a full freeze (no breathing) stopped the upload, and full freeze makes apps hang. Deep pause lowers iCloud's CPU and disk work but does not save mobile data.

Why ShyCloud uses **deep pause** (freeze `bird` but let it breathe for 0.2 s every 2 s, plus a 10 s thaw on any app launch) and not anything else. All numbers measured on a MacBook Pro M4 Pro, macOS 27.0.1, with a real iCloud Drive backlog.

## The bug that started it

With `bird` frozen (SIGSTOP), GeForce NOW and Steam would not open. Their main thread waits in a synchronous XPC call to `bird`:

`-[NSFileManager ubiquityIdentityToken]` → `BRAccount currentCachedLoggedInAccount` → `__NSXPCCONNECTION_IS_WAITING_FOR_A_SYNCHRONOUS_REPLY__`

Any app (Chromium/CEF, Electron, Finder, Open/Save panels…) can make that call at any time, so "unfreeze only for game X" can't work.

## Methods compared

| Method | How |
|---|---|
| Normal | ShyCloud off |
| Deep pause | SIGSTOP, SIGCONT for 0.2 s every 2 s, 10 s thaw on app launch (the shipped app) |
| Quiet | `PRIO_DARWIN_BG` on `bird` + `cloudd` (lowest priority, never stopped) |
| Freeze | SIGSTOP, never released (the original v1 method) |
| Nice | `nice +20` — rejected early: sync ran at full speed (5 MB in 50 s) |

## Soak test — 2 h 15 min, every method twice (20 min blocks; freeze 10 min)

Every minute: `ubiquityIdentityToken` latency (5 s cap), `git add/commit/status` in a repo on iCloud Desktop, `ls -lR` of iCloud Drive. Every 5 min: incremental `xcodebuild` of a project on iCloud Desktop. Each block: launch GeForce NOW and Steam.

| | token latency median / max | hangs | GeForce NOW / Steam window | iCloud traffic (cloudd, per block) | bird CPU | git max |
|---|---|---|---|---|---|---|
| Normal | 0.003 / 0.010 s | 0 / 50 | 2 s / 2 s | 0.5–1 GB | 145 s | 0.07 s |
| **Deep pause** | **1.48 / 1.75 s** | **0 / 48** | **2–3 s / 2 s** | **~350 KB** | 52 s | 0.08 s |
| Quiet | 0.003 / 0.004 s | 0 / 49 | 2 s / 2 s | ~820 KB | 39 s | **39.7 s** |
| Freeze | — | **19 / 21** | **31 s** / 2 s | ~200 KB | 6 s | 0.07 s |

ShyCloud's own CPU while deep-pausing: ~1 s per 20 min.

Earlier 60 s spot check with a heavy backlog: Quiet hung 4 of 5 calls (a `PRIO_DARWIN_BG` process can't be priority-boosted by the caller, so the reply waits behind the backlog).

## iCloud conflict copies ("name 2.swift")

During the soak the test repo got iCloud conflict duplicates (`Breather 2.swift` …), which broke builds. A targeted test (fresh repo per method, 15 min of commits + branch switches every 30 s, then 10 min of free sync) produced **0 conflict copies for Normal, Deep pause and Quiet**. The owner's projects on iCloud Desktop already contain 2,000+ such copies created since mid-2025, long before ShyCloud — it's iCloud + git in general, not the pause method. Best practice remains: keep git repos out of iCloud-synced folders (or a `.nosync` folder).

## Decision

- **Deep pause** is the only method that both stops sync (~0.1 % of normal traffic) and never hangs apps (worst wait 1.75 s; app launches unaffected). Shipped.
- **Quiet** — rejected: can hang under backlog and stalled git for 40 s.
- **Freeze / "really off" mode** — rejected: hangs apps (the original bug). Deep pause already reduces traffic to near zero.
- No mode picker in Settings: the menu's Sync On / Scheduled / Sync Off is enough.
