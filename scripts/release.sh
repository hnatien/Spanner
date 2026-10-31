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
stage=$out/dmg-root
mkdir -p "$stage"
ditto "$app" "$stage/Spanner.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Spanner $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"
rm -rf "$stage"
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
    --notes "Download Spanner-$version.dmg below. See the README for first-launch steps." \
    "$dmg" "$out/appcast.xml"
  print "Published https://github.com/$repo/releases/tag/$tag"
else
  print "Built $dmg and $out/appcast.xml. Rerun with --publish to upload them."
fi
