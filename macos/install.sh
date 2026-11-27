#!/bin/bash
set -eu
source_dir=$(cd "$(/usr/bin/dirname "$0")" && pwd)
root="$HOME/Library/Application Support/DisplayHandoff"
job='local.display-handoff.mac'
plist="$HOME/Library/LaunchAgents/$job.plist"
button="$HOME/Desktop/Return to Windows.app"
display=''
windows_input=15
mac_input=16
deskflow=NO
check_only=0

usage() {
    echo 'Usage: bash macos/install.sh --display UUID [--windows-input 15] [--mac-input 16] [--deskflow] [--check-only]'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --display) display="${2:?Missing display UUID}"; shift 2 ;;
        --windows-input) windows_input="${2:?Missing Windows input}"; shift 2 ;;
        --mac-input) mac_input="${2:?Missing Mac input}"; shift 2 ;;
        --deskflow) deskflow=YES; shift ;;
        --check-only) check_only=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

if ! [[ "$display" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]]; then
    echo 'Run m1ddc display list detailed and pass the shared monitor System UUID.' >&2
    exit 2
fi
for input in "$windows_input" "$mac_input"; do
    if ! [[ "$input" =~ ^[1-9][0-9]{0,2}$ ]] || [ "$input" -gt 255 ]; then
        echo 'Use decimal DDC input codes from 1 through 255.' >&2
        exit 2
    fi
done
[ "$windows_input" != "$mac_input" ] || { echo 'The two input codes must differ.' >&2; exit 2; }
ddc=$(command -v m1ddc || true)
[ -x "$ddc" ] || { echo 'Install m1ddc first and make it available in PATH.' >&2; exit 1; }
selected=$("$ddc" --read-wait 90 display "$display" get input)
if [ "$selected" != "$mac_input" ]; then
    echo "Mac read input $selected. Select the Mac input on your shared monitor and check its DDC code." >&2
    exit 1
fi
if [ "$check_only" -eq 1 ]; then echo 'Mac DDC readback verified.'; exit 0; fi

for path in "$button" "$plist"; do
    if [ -e "$path" ]; then echo "Already exists: $path. Run macos/uninstall.sh before reinstalling." >&2; exit 1; fi
done

if [ "$deskflow" = YES ]; then
    deskflow_config="$HOME/Library/Deskflow/Deskflow.conf"
    if [ ! -f "$deskflow_config" ]; then
        echo 'Configure and connect the Deskflow Mac client first, then quit it before installing.' >&2
        exit 1
    fi
    if /usr/bin/pgrep -U "$(/usr/bin/id -u)" -x 'Deskflow|deskflow|deskflow-core' >/dev/null; then
        echo 'Quit the Mac Deskflow client to apply its startup setting.' >&2
        exit 1
    fi
fi

build=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/display-handoff.XXXXXXXX")
trap '/bin/rm -rf -- "$build"' EXIT
candidate="$build/Return to Windows.app"
/usr/bin/osacompile -o "$candidate" "$source_dir/return.applescript"
/usr/bin/plutil -lint "$candidate/Contents/Info.plist"
app_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw "$candidate/Contents/Info.plist")

/bin/mkdir -p "$root/mailbox" "$HOME/Library/LaunchAgents"
/usr/bin/install -m 700 "$source_dir/agent.sh" "$root/agent.sh"
settings="$build/settings.plist"
/usr/bin/plutil -create xml1 "$settings"
/usr/bin/plutil -insert DdcTool -string "$ddc" "$settings"
/usr/bin/plutil -insert Display -string "$display" "$settings"
/usr/bin/plutil -insert WindowsInput -integer "$windows_input" "$settings"
/usr/bin/plutil -insert MacInput -integer "$mac_input" "$settings"
/usr/bin/plutil -insert Deskflow -bool "$deskflow" "$settings"
/usr/bin/install -m 600 "$settings" "$root/settings.plist"
/usr/bin/touch "$root/mailbox/events.log"

if [ "$deskflow" = YES ]; then
    /usr/bin/awk '
        /^\[/ { if (gui && !seen) print "autoHide=true"; gui = ($0 == "[gui]"); if (gui) found = 1 }
        gui && /^autoHide=/ { if (!seen++) print "autoHide=true"; next }
        { print }
        END { if (!found) print "\n[gui]\nautoHide=true"; else if (gui && !seen) print "autoHide=true" }
    ' "$deskflow_config" > "$build/Deskflow.conf"
    /usr/bin/install -m 600 "$build/Deskflow.conf" "$deskflow_config"
fi

job_config="$build/$job.plist"
/usr/bin/plutil -create xml1 "$job_config"
/usr/bin/plutil -insert Label -string "$job" "$job_config"
/usr/bin/plutil -insert ProgramArguments -array "$job_config"
/usr/bin/plutil -insert ProgramArguments -string '/bin/bash' -append "$job_config"
/usr/bin/plutil -insert ProgramArguments -string "$root/agent.sh" -append "$job_config"
/usr/bin/plutil -insert ProgramArguments -string listen -append "$job_config"
/usr/bin/plutil -insert RunAtLoad -bool YES "$job_config"
/usr/bin/plutil -insert KeepAlive -bool YES "$job_config"
/usr/bin/plutil -insert StandardErrorPath -string "$root/agent.log" "$job_config"
/usr/bin/plutil -lint "$job_config"
/usr/bin/install -m 600 "$job_config" "$plist"
/bin/mv -n "$candidate" "$HOME/Desktop/"
[ ! -e "$candidate" ] || { echo 'A conflicting desktop app appeared.' >&2; exit 1; }
printf '%s\n' "$app_id" > "$root/app-id"
/bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$plist"
echo "Installed Return to Windows.app. Share this mailbox with the Windows account: $root/mailbox"
