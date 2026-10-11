# ShyCloud — Pause iCloud Drive sync on Mac, on a schedule

[Türkçe](README.tr.md)

**ShyCloud** is a free, open-source menu bar app that keeps **iCloud Drive sync paused while you work** and lets it run only in a time window you choose — by default **02:00–09:00**. No more `bird` eating CPU and disk I/O, no more Finder stalls, no more git and Xcode fighting iCloud in the middle of your day.

- ☁️ **Scheduled sync** — iCloud Drive syncs only inside your daily window
- ⏸ **Sync Off** — vacation / travel / hotspot mode, fully paused
- ▶️ **Sync On** — normal iCloud, one click
- 🛟 **Safety first** — iCloud resumes on quit, sleep, logout and crashes (built-in safety helper), and apps never hang waiting for it
- 🫥 **Hideable** — remove the menu bar icon; it keeps working in the background
- 🍎 Apple Silicon · macOS 26+ · English · no tracking, no account

<!-- ![ShyCloud menu](docs/images/menu.png) -->

## Install

- **Download:** latest notarized DMG from [Releases](https://github.com/ekremus/shycloud/releases/latest)
- **Homebrew:** `brew install --cask ekremus/tap/shycloud`

## How it works

macOS has no public switch to pause iCloud Drive. ShyCloud does what power users do in Terminal — `kill -STOP` / `kill -CONT` on the iCloud Drive daemon `bird` — but safely and automatically.

A fully frozen `bird` has one catch: apps that ask iCloud something at launch (Steam, GeForce NOW and other Chromium-based apps) wait for an answer forever. So ShyCloud uses a **deep pause**:

- iCloud is frozen, and **released for a moment every 2 seconds** (0.2 s), so apps that ask it something get an answer within about 2 seconds instead of hanging. While paused, iCloud therefore does a small trickle of work, not none.
- When you **open an app**, iCloud runs normally for 10 seconds.
- Every 30 seconds ShyCloud checks that iCloud still answers within 3 seconds. If it doesn't, ShyCloud lets it run normally for 10 minutes before trying again.

And always:

- It only touches processes owned by **you**, matched by **exact system path** (never by name — iOS Simulator copies are never touched).
- It re-checks every process right before signalling it.
- A tiny **safety helper** (a LaunchAgent) resumes iCloud within ~3 minutes if ShyCloud ever stops unexpectedly.
- Paused processes are never killed. Nothing is deleted. Reboot or log out and iCloud is back to normal.

Optional extras in Settings: pause **Photo analysis** (`photoanalysisd`) and, under Advanced, **CloudKit** (`cloudd` — also pauses Messages, Notes, Reminders sync).

## Good to know

- **Files that are only in iCloud** (cloud icon in Finder) can't open while sync is paused. Choose **Sync On**, or turn off *Optimize Mac Storage* so files stay downloaded.
- **Why not on the Mac App Store?** App Store apps run in a sandbox that can't pause other processes.
- **How do I undo everything?** Choose *Sync On*, or quit ShyCloud, or restart your Mac.

## Uninstall

1. Quit ShyCloud from the menu (iCloud resumes right away).
2. Delete ShyCloud from Applications.

Or with Homebrew: `brew uninstall --cask --zap shycloud`.

The background safety helper is part of the app and goes away with it. You can also switch it off in System Settings › General › Login Items & Extensions.

## FAQ

**Why is iCloud Drive slow on my Mac / why does `bird` use so much CPU?** Large or frequently changing folders (code, `node_modules`, video exports) keep `bird` busy all day. ShyCloud moves that work to the night.

**Is it safe?** It uses the same stop/continue signals as `killall -STOP`, with safeguards. See [How it works](#how-it-works).

**Does it collect data?** No. The only network access is the Sparkle update check.

## Build from source

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open ShyCloud.xcodeproj
cd Packages/ShyCloudCore && swift test
```

If your checkout is in an iCloud-synced folder (Desktop/Documents), pass `-derivedDataPath /tmp/shycloud-dd` to xcodebuild.

## License

GPL-3.0-or-later — free forever; any redistributed version must stay open source. Contributions are accepted under the MIT license (see [CONTRIBUTING.md](CONTRIBUTING.md)).

Not affiliated with Apple. iCloud is a trademark of Apple Inc.
