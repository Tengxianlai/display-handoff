#!/bin/bash
set -eu
root=$(cd "$(/usr/bin/dirname "$0")" && pwd)
mailbox="$root/mailbox"
settings="$root/settings.plist"
ddc=$(/usr/bin/plutil -extract DdcTool raw "$settings")
display=$(/usr/bin/plutil -extract Display raw "$settings")
windows_input=$(/usr/bin/plutil -extract WindowsInput raw "$settings")
mac_input=$(/usr/bin/plutil -extract MacInput raw "$settings")
use_deskflow=$(/usr/bin/plutil -extract Deskflow raw "$settings")
deskflow_bundle='org.deskflow.deskflow'

emit() { printf '%s %s %s\n' "$(/bin/date +%s)" "$1" "$2" >> "$mailbox/events.log"; }

start_deskflow() {
    /usr/bin/open -gj -b "$deskflow_bundle"
}

stop_deskflow() {
    local uid pids pid attempt
    uid=$(/usr/bin/id -u)
    /usr/bin/osascript -l JavaScript - "$deskflow_bundle" <<'JXA' || true
ObjC.import('AppKit');
function run(args) {
    const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(args[0]);
    for (let index = 0; index < apps.count; index++) {
        apps.objectAtIndex(index).terminate;
    }
}
JXA
    for ((attempt=0; attempt<6; attempt++)); do
        pids=$(/usr/bin/pgrep -U "$uid" -x 'Deskflow|deskflow|deskflow-core' || true)
        [ -n "$pids" ] || return 0
        /bin/sleep 0.2
    done
    while IFS= read -r pid; do
        /bin/kill -TERM "$pid" 2>/dev/null || true
    done <<< "$pids"
    for ((attempt=0; attempt<10; attempt++)); do
        if ! /usr/bin/pgrep -U "$uid" -x 'Deskflow|deskflow|deskflow-core' >/dev/null; then return 0; fi
        /bin/sleep 0.2
    done
    echo 'Deskflow may still be running.' >&2
    return 1
}

wake() {
    local id="$1" request="$2" deadline selected
    /usr/bin/caffeinate -u -t 35 </dev/null >/dev/null 2>&1 &
    /bin/sleep 0.25
    emit "$id" wake-ready
    deadline=$((SECONDS + 24))
    while [ "$SECONDS" -lt "$deadline" ]; do
        [ "$(/bin/cat "$mailbox/wake.request" 2>/dev/null || true)" = "$request" ] || return 0
        selected=$("$ddc" --read-wait 90 display "$display" get input 2>/dev/null) || selected=''
        if [ "$selected" = "$mac_input" ]; then
            emit "$id" wake-active
            if [ "$use_deskflow" = true ]; then start_deskflow </dev/null >> "$root/agent.log" 2>&1 & fi
            return 0
        fi
        /bin/sleep 0.35
    done
    emit "$id" wake-timeout
}

listen() {
    local request last='' id request_windows request_mac age modified extra
    while true; do
        request=$(/bin/cat "$mailbox/wake.request" 2>/dev/null || true)
        if [ -n "$request" ] && [ "$request" != "$last" ]; then
            last="$request"
            read -r id request_windows request_mac extra <<< "$request"
            modified=$(/usr/bin/stat -f %m "$mailbox/wake.request" 2>/dev/null || echo 0)
            age=$(( $(/bin/date +%s) - modified ))
            if [[ "$id" =~ ^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$ ]] && [ -z "$extra" ] && [ "$age" -ge -5 ] && [ "$age" -lt 20 ]; then
                if [ "$request_windows" = "$windows_input" ] && [ "$request_mac" = "$mac_input" ]; then
                    wake "$id" "$request"
                else
                    emit "$id" input-mismatch
                fi
            fi
        fi
        /bin/sleep 0.25
    done
}

return_to_windows() {
    local id reply response deadline switch_sent=0
    id=$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')
    reply="$mailbox/return.$id.reply"
    trap "/bin/rm -f -- $(printf '%q' "$reply")" EXIT
    emit "$id" return-request
    deadline=$((SECONDS + 46))
    while [ "$SECONDS" -lt "$deadline" ]; do
        response=$(/bin/cat "$reply" 2>/dev/null || true)
        case "$response" in
            "$id ok")
                if [ "$use_deskflow" = true ]; then stop_deskflow >> "$root/agent.log" 2>&1 || true; fi
                return 0
                ;;
            "$id ready")
                if [ "$switch_sent" -eq 0 ]; then
                    switch_sent=1
                    "$ddc" display "$display" set input "$windows_input" >> "$root/agent.log" 2>&1 || true
                fi
                ;;
            "$id error "*) echo "${response#"$id error "}" >&2; return 1 ;;
        esac
        /bin/sleep 0.25
    done
    echo 'Timed out waiting for Windows. Check the listener or select the Windows input in the monitor menu.' >&2
    return 1
}

case "${1:-}" in
    listen) listen ;;
    return) return_to_windows ;;
    *) exit 2 ;;
esac
