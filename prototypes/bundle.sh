#!/bin/zsh
# Builds the spikes and wraps the TCC-sensitive ones in ad-hoc signed .app
# bundles, so macOS attributes permission requests to the spike itself rather
# than to the terminal that launched it.
set -euo pipefail
cd "${0:A:h}"
swift build -c release
bin=$(swift build -c release --show-bin-path)
mkdir -p build
for name in eventtap-spike capture-spike; do
  app="build/$name.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  cp "$bin/$name" "$app/Contents/MacOS/$name"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.spanner.phase0.$name</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
  codesign --force --sign - --identifier "dev.spanner.phase0.$name" "$app"
done
# Same binary under a fresh TCC identity, for the Accessibility-only tap test.
rm -rf build/eventtap-ax.app
cp -R build/eventtap-spike.app build/eventtap-ax.app
plutil -replace CFBundleIdentifier -string dev.spanner.phase0.eventtap-ax build/eventtap-ax.app/Contents/Info.plist
codesign --force --sign - --identifier dev.spanner.phase0.eventtap-ax build/eventtap-ax.app
cp "$bin/hotkey-spike" "$bin/smc-probe" build/
echo "built into $(pwd)/build"
