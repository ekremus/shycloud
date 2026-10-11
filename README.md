<p align="center">
  <img src="docs/images/logo.svg" width="160" alt="shyCloud logo">
</p>

<h1 align="center">shyCloud</h1>

<p align="center">Pause iCloud Drive sync on your Mac while you work. Let it sync at night.</p>

<p align="center">
  <a href="#install">Download</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="https://github.com/ekremus/shycloud">⭐ Star on GitHub</a>
</p>

shyCloud is a free menu bar app for Apple Silicon Macs. It keeps iCloud Drive paused during the day and lets it sync in a time window you choose. The default window is 02:00 to 09:00.

Why: iCloud Drive can use a lot of CPU and disk while it syncs big folders like code, `node_modules` or video exports. Your Mac gets slow, Finder stalls and git or Xcode can clash with iCloud.

## Features

- **Scheduled:** iCloud Drive syncs only in your daily window.
- **Sync Off:** iCloud stays paused until you turn it back on.
- **Sync On:** normal iCloud.
- **Safe:** iCloud comes back when you quit shyCloud, when the Mac sleeps or logs out, and if shyCloud crashes.
- **Apps keep working:** an app that asks iCloud something waits 2 seconds at most.
- **Hideable:** you can remove the menu bar icon. shyCloud keeps running.
- **Private:** no account, no tracking.

Requires macOS 26 or later on Apple Silicon. Tested on macOS 27.0.1 (MacBook Pro M4 Pro). Not yet tested on macOS 26.

## Install

The first signed release is coming soon. Until then you can [build from source](#build-from-source).

## How it works

macOS has no public way to pause iCloud Drive. shyCloud stops the iCloud Drive process (`bird`) with the same signal as `kill -STOP`.

A fully stopped `bird` makes some apps freeze. Steam, GeForce NOW and other Chromium apps ask iCloud a question when they open and wait for the answer. So shyCloud does a deep pause:

- `bird` is stopped but gets 0.2 seconds to run every 2 seconds. Apps get their answer in under 2 seconds.
- When you open an app, iCloud runs normally for 10 seconds.
- Every 30 seconds shyCloud checks that iCloud answers within 3 seconds. If it does not, iCloud runs normally for 10 minutes.

During a deep pause the iCloud Drive process uses about a third of its normal CPU time in our tests, so it stops competing with your work. It does not stop all network use. New files can still upload, because the transfer itself runs in a separate system process. The full results are in [docs/pause-method-study-2026-10-11.md](docs/pause-method-study-2026-10-11.md).

Safety rules:

- shyCloud only touches your own processes and finds them by their exact system path. It never touches iOS Simulator copies.
- It checks each process again right before it signals it.
- A small background helper turns iCloud back on within about 3 minutes if shyCloud stops unexpectedly.
- Nothing is killed or deleted. A restart always brings iCloud back to normal.

In Settings you can also pause iCloud Photos (`cloudphotod`), photo analysis (`photoanalysisd`) and CloudKit (`cloudd`). Pausing CloudKit also pauses Messages, Notes and Reminders sync.

## Good to know

- **Files stored only in iCloud** (cloud icon in Finder) open after sync resumes. Choose Sync On if you need one now.
- **Not on the Mac App Store** because App Store apps can't pause other processes.
- **To undo everything,** choose Sync On, quit shyCloud or restart your Mac.
- **Git repos in iCloud folders** can get duplicate files named like `file 2.swift`. iCloud does this on its own. Keep repos outside Desktop and Documents if you can.

## Uninstall

1. Quit shyCloud from its menu. iCloud resumes right away.
2. Move shyCloud from Applications to the Trash.

The background helper is part of the app and goes away with it.

## Build from source

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
open ShyCloud.xcodeproj
cd Packages/ShyCloudCore && swift test
```

If the project is in an iCloud folder (Desktop or Documents), add `-derivedDataPath /tmp/shycloud-dd` to `xcodebuild`.

## License

GPL-3.0-or-later. shyCloud is free and any copy you share must stay open source. Contributions are accepted under the MIT license, see [CONTRIBUTING.md](CONTRIBUTING.md).

shyCloud is not made by Apple. iCloud is a trademark of Apple Inc.

If shyCloud helps you, please [star it on GitHub](https://github.com/ekremus/shycloud). It helps other Mac users find it.
