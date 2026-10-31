#!/bin/zsh
# Phase 0 round 3: the two permission-dependent checks, run after the user
# has already enabled the switches in System Settings.
set -u
cd "${0:A:h}"
r=$PWD/results
drain() { while read -t 0 -k 1 _; do :; done; }
print "Before continuing, in System Settings > Privacy & Security:"
print "  - Accessibility: turn ON eventtap-ax (leave Input Monitoring alone)"
print "  - Screen & System Audio Recording: turn ON capture-spike"
print "Also minimize one window and put another on a second Space."
drain; read "?Done? [Enter] "
rm -rf "$r/thumbs"
open -W -n build/capture-spike.app --args --log "$r/capture5.log" --out "$r" --max 40
print "\nNow click into this window and, for 12 s, hold Shift/Option and type letters."
drain; read "?Ready? [Enter] "
open -W -n build/eventtap-ax.app --args --mode keys --seconds 12 --log "$r/eventtap-ax2.log"
drain
print "\nDone. Tell Claude you're finished."
