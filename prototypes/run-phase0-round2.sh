#!/bin/zsh
# Phase 0 round 2: Accessibility-only event tap, blank-thumbnail check, and
# the MagSafe LED write. Logs land in prototypes/results/.
set -u
cd "${0:A:h}"
r=$PWD/results
drain() { while read -t 0 -k 1 _; do :; done; }
pause() { drain; read "?$1 [Enter] "; }
step() { print -P "\n%B== $1 ==%b"; }

step "1/3 Keyboard tap with Accessibility only"
print "macOS will ask to grant Accessibility to eventtap-ax."
print "Enable eventtap-ax under Accessibility ONLY. Do not add it to Input Monitoring."
open -W -n build/eventtap-ax.app --args --mode keys --seconds 2 --request-ax --log "$r/eventtap-ax.log"
pause "Accessibility enabled for eventtap-ax?"
print "For 12 s: press Cmd/Option/Shift and type letters. Do not press Enter."
pause "Ready?"
open -W -n build/eventtap-ax.app --args --mode keys --seconds 12 --log "$r/eventtap-ax.log"

step "2/3 Thumbnails of minimized and other-Space windows"
print "The rebuilt capture-spike needs Screen Recording again. Enable it when asked."
open -W -n build/capture-spike.app --args --log "$r/capture4.log" --out "$r" --max 40
pause "Enabled? Now minimize one window and move another to a second Space, then"
rm -rf "$r/thumbs"
open -W -n build/capture-spike.app --args --log "$r/capture4.log" --out "$r" --max 40

step "3/3 MagSafe LED write (sudo, auto-restored after 6 s)"
print "Keep the MagSafe charger plugged in and watch the LED: it should turn off, then come back."
print "Type your password ONLY at the 'Password:' prompt."
drain
read "?Run it? [y/N] " yn
if [[ $yn == [yY] ]]; then
  sudo ./build/smc-probe write ACLC 01 6 | tee "$r/smc-aclc.log"
  drain
  read "?Did the LED turn off and then come back? [y/n] " led
  print "user: LED off then restored = $led" >> "$r/smc-aclc.log"
else
  print "skipped by user" > "$r/smc-aclc.log"
fi
step "Done. Tell Claude you're finished."
