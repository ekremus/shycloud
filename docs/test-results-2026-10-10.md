# Manual test results — 2026-10-10

Machine: MacBook Pro M4 Pro, macOS 27.0.1. Build: clean Debug at 7dd1a37, installed to /Applications. Rows from `docs/TESTING.md`. Driven from the command line (mode/settings via `defaults` + relaunch; state via `ps`), no UI clicks.

| # | Result | Evidence |
|---|---|---|
| 1 | PASS | Watchdog registered (`runs = 1`, exit 0), `watchdog-ran` + `heartbeat` written; `bird` → `T` on first tick (outside window) |
| 2 | PASS | mode `alwaysPause` → `bird` `T` within ~2 s of launch |
| 4 | PASS | Window 18:04–18:06: `bird` `T` → `S` at 18:04:28, `S` → `T` at 18:06:29 (≤ 30 s after each boundary) |
| 5 | PASS | CloudKit on: user `cloudd` (pid 695) `T`; Simulator `cloudd` and root `cloudd` untouched |
| 6 | PASS (pause half) | Photo analysis on: `/System/...photoanalysisd` `T`; Simulator copy untouched. Untick-resume not exercised via UI (covered by unit tests) |
| 7 | PASS | `kill -9 bird` → respawned `bird` paused (`T`) after 9 s |
| 9 | PASS | Outside the window in Scheduled mode nothing ran on its own |
| 13 | PASS | `kill -9 ShyCloud` while all targets paused → watchdog resumed all after 153 s |
| 14 | PASS | Relaunch after crash: paused in 2 s, no flapping over 100 s including watchdog runs |
| 16 | PASS | `showInMenuBar=false`, relaunch, open again → Settings window (440 pt wide) appeared |
| 21 | PASS | Watchdog run by hand: exit 0, `bird` stays `S` |
| 22 | PASS | `kill -TERM ShyCloud` → app quit, `bird` `S` immediately |
| 24 | PASS | `watchdog-ran` + registered path removed → re-registered, watchdog ran at 1 s, no pause until first tick, paused at 32 s |

Not yet run (need UI clicks, sleep, logout or a DMG): 3 (via menu), 8, 10, 11, 12, 15, 17, 18, 20, 23, menu icon/labels visual check, README screenshot.
