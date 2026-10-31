#!/bin/zsh
# Guided Phase 0 run: each step needs a human (key presses, permission
# prompts, or sudo). Logs land in prototypes/results/ for later analysis.
set -u
cd "${0:A:h}"
[[ -x build/smc-probe ]] || ./bundle.sh
mkdir -p results
log=results
step() { print -P "\n%B== $1 ==%b"; }
# Discard keys typed during a test so they cannot answer the next prompt.
drain() { while read -t 0 -k 1 _; do :; done; }
pause() { drain; read "?$1 [Enter] "; }

step "1/5 Cmd+Tab override"
print "The system switcher is disabled for 20 s. Press Cmd+Tab 3 times; it should NOT appear."
pause "Ready?"
./build/hotkey-spike manual 20 | tee $log/hotkey.log
./build/hotkey-spike status | tee -a $log/hotkey.log

step "2/5 Listen-only event tap, no permissions"
rm -f $log/eventtap.log
for mode in flags keys; do
  print "Mode '$mode' runs 12 s: press Cmd/Option/Shift and type a few letters. Note any permission dialog."
  pause "Ready?"
  open -W -n build/eventtap-spike.app --args --mode $mode --seconds 12 --log "$PWD/$log/eventtap.log"
done
pause "Did an 'Input Monitoring' / 'receive keystrokes' dialog appear? Answer in the next line, then Enter."
drain; read "?Answer: " answer; print "user: input-monitoring dialog seen = $answer" >> $log/eventtap.log

step "3/5 Event tap with Accessibility"
print "A dialog asks to grant Accessibility to eventtap-spike. Enable it in System Settings, then come back."
open -W -n build/eventtap-spike.app --args --mode keys --seconds 3 --request-ax --log "$PWD/$log/eventtap.log"
pause "Accessibility granted?"
print "Keys mode again for 12 s: press modifiers and type."
open -W -n build/eventtap-spike.app --args --mode keys --seconds 12 --log "$PWD/$log/eventtap.log"

step "4/5 Screen Recording + thumbnail capture"
rm -f $log/capture.log
print "First run asks for Screen Recording. Allow it in System Settings (macOS may ask to quit & reopen; choose Later)."
open -W -n build/capture-spike.app --args --log "$PWD/$log/capture.log" --out "$PWD/$log"
pause "Granted? Put a window on another Space or minimize one if you can, then"
open -W -n build/capture-spike.app --args --log "$PWD/$log/capture.log" --out "$PWD/$log"

step "5/5 SMC writes (sudo, auto-restored)"
print "Writes CHIE=08 (cut the charger) for 10 s, then ACLC=01 (MagSafe LED off) for 6 s. Both restore automatically."
print "Keep the charger plugged in. Skip with n."
drain; read "?Run the SMC write tests? [y/N] " yn
if [[ $yn == [yY] ]]; then
  sudo ./build/smc-probe write CHIE 08 10 | tee $log/smc-write.log
  sudo ./build/smc-probe write ACLC 01 6 | tee -a $log/smc-write.log
else
  print "skipped by user" > $log/smc-write.log
fi
./build/smc-probe read > $log/smc-read.log

step "Done"
print "Logs are in $PWD/$log. Tell Claude you're finished."
