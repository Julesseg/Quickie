#!/bin/bash
# Set the simulator's hardware-keyboard connection. $1 = YES|NO
#
# Order matters: Simulator.app caches its preferences and flushes them on quit,
# so a write made while it is running is clobbered the moment it exits. Quit
# first, write second, relaunch third.
set -u
UDID=B63BDB19-DB83-4FC9-AC91-8B47C442367C
PLIST=~/Library/Preferences/com.apple.iphonesimulator.plist
WANT=$1
if [ "$WANT" = YES ]; then BOOLV=true; else BOOLV=false; fi

echo "=== hardware keyboard -> $WANT ==="

# 1 · quit Simulator so it stops owning the preference
osascript -e 'tell application "Simulator" to quit' >/dev/null 2>&1
for _ in $(seq 1 20); do
  pgrep -x Simulator >/dev/null || break
  sleep 1
done
pkill -x Simulator >/dev/null 2>&1
sleep 2
# cfprefsd caches too — make it forget this domain before we write
killall -u "$USER" cfprefsd >/dev/null 2>&1
sleep 2

# 2 · write both the global default and the per-device override
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool "$WANT"
/usr/libexec/PlistBuddy -c "Set :DevicePreferences:$UDID:ConnectHardwareKeyboard $BOOLV" "$PLIST" >/dev/null 2>&1 \
  || /usr/libexec/PlistBuddy -c "Add :DevicePreferences:$UDID:ConnectHardwareKeyboard bool $BOOLV" "$PLIST" >/dev/null 2>&1
killall -u "$USER" cfprefsd >/dev/null 2>&1
sleep 1
echo -n "  global=";      defaults read com.apple.iphonesimulator ConnectHardwareKeyboard
echo -n "  per-device=";  /usr/libexec/PlistBuddy -c "Print :DevicePreferences:$UDID:ConnectHardwareKeyboard" "$PLIST" 2>/dev/null

# 3 · relaunch and let it settle
open -a Simulator --args -CurrentDeviceUDID "$UDID"
sleep 16
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
echo "  simulator up"
