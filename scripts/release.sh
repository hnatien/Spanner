#!/bin/zsh
# Builds a Spanner release into build/release/<version>/: a signed DMG and a
# Sparkle appcast that lists it. With --publish, uploads both to a GitHub
# release on the public releases repo, where the app's SUFeedURL points.
#
#   scripts/release.sh [--publish]
#
# The version comes from MARKETING_VERSION and CURRENT_PROJECT_VERSION in
# project.yml. Sparkle compares CURRENT_PROJECT_VERSION, so bump it every
# release.
#
# Signing: by default the build is signed per Config/Signing.xcconfig, so run
# scripts/setup-signing.sh first. Ad-hoc builds are refused because macOS
# would drop users' Accessibility grants on every update. If a "Developer ID
# Application" certificate is in the keychain, the build is signed with it and
# notarized; set NOTARY_PROFILE to a profile saved with
# `xcrun notarytool store-credentials`.
set -euo pipefail
cd "${0:A:h}/.."

repo=hnatien/Spanner-releases
feed="https://github.com/$repo/releases/latest/download/appcast.xml"
derived=build/DerivedData
sparkle_bin=$derived/SourcePackages/artifacts/sparkle/Sparkle/bin

# Install guide shown on every GitHub release page.
release_notes() {
  cat <<NOTES
## Install

1. Download **Spanner-$version.dmg** below. Spanner needs macOS 15 or later.
2. Open the DMG and drag **Spanner** into **Applications**.
3. Open Spanner. Because the app isn't notarized by Apple yet, macOS blocks the first launch. Go to **System Settings › Privacy & Security**, scroll down to the message about Spanner, and click **Open Anyway**. Or run:

   \`\`\`bash
   xattr -dr com.apple.quarantine /Applications/Spanner.app
   \`\`\`

4. Grant the permissions each module asks for (Accessibility, Screen Recording, System Audio Recording) in the onboarding guide.

Spanner lives in the menu bar, not the Dock. Later versions arrive through its built-in updater and don't need step 3 again.
NOTES
}

publish=false
for arg; do
  case $arg in
    --publish) publish=true ;;
    *) print -u2 "Usage: scripts/release.sh [--publish]"; exit 64 ;;
  esac
done

version=$(awk '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
build_number=$(awk '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' project.yml)
if [[ -z "$version" || -z "$build_number" ]]; then
  print -u2 "Could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml."
  exit 1
fi
tag="v$version"
out=build/release/$version
dmg=$out/Spanner-$version.dmg

if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 "Warning: the working tree has uncommitted changes; they will be in this build."
fi

if $publish; then
  if ! gh repo view "$repo" >/dev/null 2>&1; then
    print -u2 "GitHub repo $repo not found. Create it (public) first:"
    print -u2 "  gh repo create $repo --public --description \"Spanner downloads and update feed\""
    exit 1
  fi
  if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then
    print -u2 "Release $tag already exists on $repo. Bump MARKETING_VERSION in project.yml."
    exit 1
  fi
fi

# Developer ID builds override the xcconfig signing and get notarized.
sign_settings=()
notarize=false
developer_id=$(security find-identity -v -p codesigning \
  | sed -nE 's/.*"(Developer ID Application:[^"]*)".*/\1/p' | head -1)
if [[ -n "$developer_id" ]]; then
  if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    print -u2 "Found \"$developer_id\" but NOTARY_PROFILE is not set."
    print -u2 "Save credentials with: xcrun notarytool store-credentials <profile>"
    exit 1
  fi
  team=$(security find-certificate -c "$developer_id" -p | openssl x509 -noout -subject -nameopt multiline \
    | awk -F' = ' '/organizationalUnitName/ { print $2; exit }')
  sign_settings=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$developer_id" "DEVELOPMENT_TEAM=$team"
                 "OTHER_CODE_SIGN_FLAGS=--timestamp")
  notarize=true
fi

rm -rf "$out"
mkdir -p "$out"

print "Archiving Spanner $version ($build_number)…"
xcodegen generate --quiet
xcodebuild archive -quiet \
  -project Spanner.xcodeproj -scheme Spanner -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$out/Spanner.xcarchive" -derivedDataPath "$derived" \
  "${sign_settings[@]}"

app=$out/Spanner.xcarchive/Products/Applications/Spanner.app
built_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
if [[ "$built_version" != "$version" ]]; then
  print -u2 "Built app reports version $built_version, expected $version."
  exit 1
fi

codesign --verify --deep --strict "$app"
identity=$(codesign -dvv "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)
if [[ -z "$identity" ]]; then
  print -u2 "The app is ad-hoc signed. Run scripts/setup-signing.sh, then rerun."
  exit 1
fi
print "Signed with \"$identity\"."

print "Building $dmg…"
volume="Spanner $version"
if [[ -e "/Volumes/$volume" ]]; then
  print -u2 "A volume named \"$volume\" is already mounted. Eject it, then rerun."
  exit 1
fi
stage=$out/dmg-root
rw_dmg=$out/Spanner-rw.dmg
mkdir -p "$stage/.background"
ditto "$app" "$stage/Spanner.app"
ln -s /Applications "$stage/Applications"
swift scripts/make-dmg-background.swift "$stage/.background/background.tiff"
hdiutil create -quiet -volname "$volume" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$rw_dmg"
rm -rf "$stage"

# Lay out the install window in Finder; it saves the layout to the volume's
# .DS_Store. Icon positions match scripts/make-dmg-background.swift.
hdiutil attach -quiet -readwrite -noverify -noautoopen "$rw_dmg"
osascript - "$volume" <<'APPLESCRIPT'
on run {volumeName}
  tell application "Finder"
    tell disk volumeName
      -- Settings made before the window has finished opening are dropped.
      open
      delay 1
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 120, 860, 608}
      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 112
      set text size of viewOptions to 13
      set background picture of viewOptions to file ".background:background.tiff"
      set position of item "Spanner.app" of container window to {170, 185}
      set position of item "Applications" of container window to {490, 185}
      -- Closing right away drops the view options; give Finder time to
      -- save them to .DS_Store first.
      update without registering applications
      delay 2
      close
    end tell
  end tell
end run
APPLESCRIPT
# Finder writes .DS_Store a moment after the window closes.
for _ in {1..20}; do
  grep -qa backgroundImageAlias "/Volumes/$volume/.DS_Store" 2>/dev/null && break
  sleep 0.5
done
if ! grep -qa backgroundImageAlias "/Volumes/$volume/.DS_Store" 2>/dev/null; then
  hdiutil detach -quiet "/Volumes/$volume"
  print -u2 "Finder did not save the DMG window layout."
  exit 1
fi
# Finder overwrites .DS_Store with a default layout when the volume
# unmounts, so put the saved one back through a mount Finder doesn't track.
cp "/Volumes/$volume/.DS_Store" "$out/layout.DS_Store"
hdiutil detach -quiet "/Volumes/$volume"
hdiutil attach -quiet -readwrite -noverify -noautoopen -nobrowse -mountpoint "$out/dmg-mount" "$rw_dmg"
cp "$out/layout.DS_Store" "$out/dmg-mount/.DS_Store"
hdiutil detach -quiet "$out/dmg-mount"
rm -f "$out/layout.DS_Store"
hdiutil convert -quiet "$rw_dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg"
rm -f "$rw_dmg"
if $notarize; then
  codesign --sign "$identity" --timestamp "$dmg"
else
  codesign --sign "$identity" "$dmg"
fi

if $notarize; then
  print "Notarizing (this can take a few minutes)…"
  result=$(xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
  notary_status=$(print -r -- "$result" | plutil -extract status raw -o - -)
  if [[ "$notary_status" != "Accepted" ]]; then
    print -u2 "Notarization finished with status \"$notary_status\":"
    print -u2 -r -- "$result"
    exit 1
  fi
  xcrun stapler staple "$dmg"
  spctl -a -vvv -t install "$dmg"
fi

# Start from the published appcast so earlier versions stay listed.
if curl -fsSL "$feed" -o "$out/appcast.xml" 2>/dev/null; then
  if grep -q "<sparkle:version>$build_number</sparkle:version>" "$out/appcast.xml"; then
    print -u2 "The published appcast already has build $build_number. Bump CURRENT_PROJECT_VERSION in project.yml."
    exit 1
  fi
else
  rm -f "$out/appcast.xml"
fi

print "Generating appcast…"
"$sparkle_bin/generate_appcast" \
  --download-url-prefix "https://github.com/$repo/releases/download/$tag/" \
  --link "https://github.com/$repo" \
  "$out"

if $publish; then
  print "Publishing $tag to $repo…"
  gh release create "$tag" -R "$repo" --title "Spanner $version" \
    --notes "$(release_notes)" "$dmg" "$out/appcast.xml"
  print "Published https://github.com/$repo/releases/tag/$tag"
else
  print "Built $dmg and $out/appcast.xml. Rerun with --publish to upload them."
fi
