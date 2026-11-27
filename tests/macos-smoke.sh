#!/bin/bash
set -eu
project=$(cd "$(/usr/bin/dirname "$0")/.." && pwd)
fixture=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/display-handoff-test.XXXXXXXX")
listener=''
client=''
cleanup() {
    if [ -n "$listener" ]; then kill "$listener" 2>/dev/null || true; fi
    if [ -n "$client" ]; then kill "$client" 2>/dev/null || true; fi
    /bin/rm -rf -- "$fixture"
}
trap cleanup EXIT

for script in "$project"/macos/*.sh; do /bin/bash -n "$script"; done
/usr/bin/osacompile -o "$fixture/Return to Windows.app" "$project/macos/return.applescript"
/usr/bin/plutil -lint "$fixture/Return to Windows.app/Contents/Info.plist"

mailbox="$fixture/mailbox"
events="$mailbox/events.log"
/bin/mkdir "$mailbox"
/usr/bin/touch "$events"
/bin/cp "$project/macos/agent.sh" "$fixture/agent.sh"
/bin/cat > "$fixture/m1ddc" <<'DDC'
#!/bin/bash
directory=$(cd "$(/usr/bin/dirname "$0")" && pwd)
if [ "${3:-}" = set ]; then
    printf '%s\n' "$5" > "$directory/input"
else
    /bin/cat "$directory/input"
fi
DDC
/bin/chmod 700 "$fixture/m1ddc"
printf '15\n' > "$fixture/input"
settings="$fixture/settings.plist"
/usr/bin/plutil -create xml1 "$settings"
/usr/bin/plutil -insert DdcTool -string "$fixture/m1ddc" "$settings"
/usr/bin/plutil -insert Display -string '00000000-0000-0000-0000-000000000001' "$settings"
/usr/bin/plutil -insert WindowsInput -integer 15 "$settings"
/usr/bin/plutil -insert MacInput -integer 16 "$settings"
/usr/bin/plutil -insert Deskflow -bool NO "$settings"

wait_for() {
    local pattern="$1" file="$2" deadline=$((SECONDS + 8))
    until /usr/bin/grep -Eq "$pattern" "$file"; do
        if [ "$SECONDS" -ge "$deadline" ]; then echo "Missing event $pattern" >&2; /bin/cat "$events"; exit 1; fi
        /bin/sleep 0.15
    done
}

/bin/bash "$fixture/agent.sh" listen &
listener=$!
id='81e2bce5-1dce-4e5d-b65e-2646baccadcd'
printf '%s 15 16' "$id" > "$mailbox/wake.request"
wait_for " $id wake-ready$" "$events"
printf '16\n' > "$fixture/input"
wait_for " $id wake-active$" "$events"
/bin/rm -f "$mailbox/wake.request"

/bin/bash "$fixture/agent.sh" return &
client=$!
wait_for ' return-request$' "$events"
return_id=$(/usr/bin/awk '$3 == "return-request" { print $2 }' "$events")
printf '%s ready' "$return_id" > "$mailbox/return.$return_id.reply"
wait_for '^15$' "$fixture/input"
printf '%s ok' "$return_id" > "$mailbox/return.$return_id.reply"
wait "$client"
client=''
echo 'Finder app compiled and both Mac handoff directions passed with simulated DDC.'
