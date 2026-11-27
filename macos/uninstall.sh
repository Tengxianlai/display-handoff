#!/bin/bash
set -eu
root="$HOME/Library/Application Support/DisplayHandoff"
job='local.display-handoff.mac'
plist="$HOME/Library/LaunchAgents/$job.plist"
app="$HOME/Desktop/Return to Windows.app"
[ -f "$root/settings.plist" ] || exit 0
/bin/launchctl bootout "gui/$(/usr/bin/id -u)/$job" 2>/dev/null || true
/bin/rm -f -- "$plist"
if [ -f "$root/app-id" ] && [ -f "$app/Contents/Info.plist" ]; then
    expected=$(/bin/cat "$root/app-id")
    actual=$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" 2>/dev/null || true)
    if [ "$actual" = "$expected" ] && [ -n "$expected" ]; then
        /bin/mv "$app" "$root/Return to Windows $(/bin/date +%Y%m%d-%H%M%S).app"
    fi
fi
echo "Stopped Display Handoff. Local data is at $root. Remove its mailbox from File Sharing."
