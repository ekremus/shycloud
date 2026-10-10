#!/usr/bin/env bash
# Release ShyCloud: archive → Developer ID sign → notarize → DMG → Sparkle appcast → GitHub release → Homebrew cask.
# Prerequisites (one time):
#   1. "Developer ID Application" certificate in the login keychain (developer.apple.com → Certificates).
#   2. xcrun notarytool store-credentials shycloud-notary --apple-id <id> --team-id LQJCF4Z633
#   3. Sparkle private key in the keychain (generate_keys, Task 10).
#   4. gh auth login; GitHub Pages serving /docs on main for github.com/ekremus/shycloud.
#   5. Repo github.com/ekremus/homebrew-tap cloned next to this repo (../homebrew-tap).
# All build products live outside the repo (it may sit in an iCloud-synced folder, which breaks codesign).
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version>  e.g. 1.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD=/private/tmp/shycloud-release-dd
DIST=/private/tmp/shycloud-dist
APP="$DIST/export/ShyCloud.app"
DMG="$DIST/ShyCloud-$VERSION.dmg"
cd "$ROOT"
if ! git diff --quiet || ! git diff --cached --quiet; then echo "Working tree not clean" >&2; exit 1; fi
[ "$(git branch --show-current)" = main ] || { echo "Must be on main" >&2; exit 1; }
BUILD=$(git rev-list --count HEAD)

notarize() {
  local out status id
  out=$(xcrun notarytool submit "$1" --keychain-profile shycloud-notary --wait --output-format json)
  status=$(printf '%s' "$out" | /usr/bin/plutil -extract status raw -o - -)
  if [ "$status" != "Accepted" ]; then
    id=$(printf '%s' "$out" | /usr/bin/plutil -extract id raw -o - - || true)
    echo "Notarization failed ($status)" >&2
    xcrun notarytool log "$id" --keychain-profile shycloud-notary || true
    exit 1
  fi
}

rm -rf "$DIST" && mkdir -p "$DIST"

xcodegen generate
xcodebuild -project ShyCloud.xcodeproj -scheme ShyCloud -configuration Release \
  -derivedDataPath "$DD" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  -archivePath "$DIST/ShyCloud.xcarchive" archive

cat > "$DIST/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>LQJCF4Z633</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$DIST/ShyCloud.xcarchive" -exportOptionsPlist "$DIST/export.plist" -exportPath "$DIST/export"

codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/ShyCloud" | grep -qx arm64

ditto -c -k --keepParent "$APP" "$DIST/ShyCloud.zip"
notarize "$DIST/ShyCloud.zip"
xcrun stapler staple "$APP"

mkdir -p "$DIST/dmg" && cp -R "$APP" "$DIST/dmg/" && ln -s /Applications "$DIST/dmg/Applications"
hdiutil create -volname ShyCloud -srcfolder "$DIST/dmg" -ov -format UDZO "$DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

GENERATE_APPCAST=$(find "$DD/SourcePackages/artifacts" -path "*Sparkle/bin/generate_appcast" -type f | head -1)
mkdir -p "$DIST/appcast" && cp "$DMG" "$DIST/appcast/"
[ -f docs/appcast.xml ] && cp docs/appcast.xml "$DIST/appcast/appcast.xml"
"$GENERATE_APPCAST" --download-url-prefix "https://github.com/ekremus/shycloud/releases/download/v$VERSION/" "$DIST/appcast"
cp "$DIST/appcast/appcast.xml" docs/appcast.xml

gh release create "v$VERSION" "$DMG" --title "ShyCloud $VERSION" --notes-file <(awk -v v="$VERSION" '$0 == "## " v {f=1;next} /^## /{f=0} f' CHANGELOG.md)
git add docs/appcast.xml && git commit -m "release: appcast for $VERSION" && git push

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
mkdir -p ../homebrew-tap/Casks
cat > ../homebrew-tap/Casks/shycloud.rb <<CASK
cask "shycloud" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/ekremus/shycloud/releases/download/v#{version}/ShyCloud-#{version}.dmg"
  name "ShyCloud"
  desc "Pause iCloud Drive sync on a schedule"
  homepage "https://github.com/ekremus/shycloud"

  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  auto_updates true

  app "ShyCloud.app"

  uninstall quit:      "com.ekremus.ShyCloud",
            launchctl: "com.ekremus.ShyCloud.Watchdog"
  zap trash: [
    "~/Library/Application Support/ShyCloud",
    "~/Library/Preferences/com.ekremus.ShyCloud.plist",
  ]
end
CASK
(cd ../homebrew-tap && git add Casks/shycloud.rb && git commit -m "shycloud $VERSION" && git push)
echo "Released ShyCloud $VERSION"
