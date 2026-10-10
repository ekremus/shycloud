# ShyCloud — Pause iCloud Drive sync on Mac, on a schedule

[Türkçe](README.tr.md)

**ShyCloud** is a free, open-source menu bar app that keeps **iCloud Drive sync paused while you work** and lets it run only in a time window you choose — by default **02:00–09:00**. No more `bird` eating CPU and disk I/O, no more Finder stalls, no more git and Xcode fighting iCloud in the middle of your day.

- ☁️ **Scheduled sync** — iCloud Drive syncs only inside your daily window
- ⏸ **Sync Off** — vacation / travel / hotspot mode, fully paused
- ▶️ **Sync On** — normal iCloud, one click
- 🛟 **Safety first** — iCloud always resumes on quit, sleep, logout, crash (built-in safety helper)
- 🌙 **Catch-up** — slept through the window? It syncs 30 minutes after you wake
- 🫥 **Hideable** — remove the menu bar icon; it keeps working in the background
- 🍎 Apple Silicon · macOS 26+ · English & Türkçe · no tracking, no account

![ShyCloud menu](docs/images/menu.png)

## Install

- **Download:** latest notarized DMG from [Releases](https://github.com/ekremus/shycloud/releases/latest)
- **Homebrew:** `brew install --cask ekremus/tap/shycloud`

## How it works

macOS has no public switch to pause iCloud Drive. ShyCloud does what power users do in Terminal — `kill -STOP` / `kill -CONT` on the iCloud Drive daemon `bird` — but safely and automatically:

- It only touches processes owned by **you**, matched by **exact system path** (never by name — iOS Simulator copies are never touched).
- It re-checks every process right before signalling it.
- A tiny **safety helper** (a LaunchAgent) resumes iCloud within ~3 minutes if ShyCloud ever stops unexpectedly.
- Paused processes are never killed. Nothing is deleted. Reboot or log out and iCloud is back to normal.

Optional extras in Settings: pause **Photo analysis** (`photoanalysisd`) and, under Advanced, **CloudKit** (`cloudd` — also pauses Messages, Notes, Reminders sync).

## Good to know

- **Files that are only in iCloud** (cloud icon in Finder) can't open while sync is paused. Choose **Sync On**, or turn off *Optimize Mac Storage* so files stay downloaded.
- **Why not on the Mac App Store?** App Store apps run in a sandbox that can't pause other processes.
- **How do I undo everything?** Choose *Sync On*, or quit ShyCloud, or restart your Mac.

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
