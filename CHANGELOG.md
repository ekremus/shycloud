# Changelog

## 1.0.0 (unreleased)

- Three modes in the menu: Scheduled, Sync On and Sync Off. The default sync window is 02:00 to 09:00.
- While paused, iCloud Drive stays stopped, so new files do not upload.
- iCloud runs normally for 10 seconds when you open an app or switch to one (at most once a minute per app).
- Optional breathing mode (Let apps reach iCloud while paused): iCloud Drive runs for 0.2 seconds every 2 seconds, so apps that ask iCloud something get an answer in under 2 seconds. Uploads keep going in this mode.
- In breathing mode, if iCloud stops answering, shyCloud lets it run normally for 10 minutes.
- Optional pausing of photo analysis and CloudKit.
- A background helper turns iCloud back on if shyCloud stops unexpectedly.
- Quitting, sleep and logout always turn iCloud back on.
- Hideable menu bar icon. New logo and app icon.
