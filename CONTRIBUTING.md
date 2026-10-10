# Contributing to ShyCloud

Thanks for helping! Bug reports, translations and pull requests are welcome.

## Licensing of contributions
ShyCloud is distributed under GPL-3.0-or-later. **By submitting a contribution you license it under the MIT license**, which also allows the maintainer to include it in future versions under other licenses. If you can't agree to this, please open an issue instead of a PR.

## Development
- Xcode 27, XcodeGen: `xcodegen generate`
- Core logic and tests: `cd Packages/ShyCloudCore && swift test`
- Keep all process-signalling code inside `SignalProcessController`. Never match processes by name.
- Manual checks: `docs/TESTING.md`

## Translations
The app UI is English only for now. Strings live in `App/Localizable.xcstrings`, so a language can be added later if the maintainer decides to; please open an issue first.
