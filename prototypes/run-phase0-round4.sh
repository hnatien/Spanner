#!/bin/zsh
# Phase 0 round 4: blank-thumbnail check with a fresh Screen Recording grant.
set -u
cd "${0:A:h}"
r=$PWD/results
drain() { while read -t 0 -k 1 _; do :; done; }
print "1. In Screen & System Audio Recording, select capture-spike and click the minus (-) button."
drain; read "?Removed? [Enter] "
open -W -n build/capture-spike.app --args --log "$r/capture6.log" --out "$r" --max 2
print "2. capture-spike should be back in the list now. Turn it ON (choose Later if asked to quit)."
print "3. Minimize one window and move another window to a second Space."
drain; read "?Done? [Enter] "
rm -rf "$r/thumbs"
open -W -n build/capture-spike.app --args --log "$r/capture6.log" --out "$r" --max 40
print "\nFinished. Tell Claude."
