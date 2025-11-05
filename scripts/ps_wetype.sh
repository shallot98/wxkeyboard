#!/bin/sh
set -eu

echo "==> WeType / wxkeyboard process scan"

if command -v ps >/dev/null 2>&1; then
    ps -eo pid,comm,args | awk 'NR==1 {print; next} {line=tolower($0); if (line ~ /wetype/ || line ~ /wxkeyboard/) print $0}'
else
    echo "ps command not available on this system."
fi

if command -v launchctl >/dev/null 2>&1 && command -v ps >/dev/null 2>&1; then
    echo ""
    echo "==> launchctl procinfo (bundle identifiers)"
    ps -eo pid,comm | awk 'NR>1 {if (tolower($2) ~ /wetype/) print $1}' | while read pid; do
        [ -n "$pid" ] || continue
        echo "-- PID $pid --"
        launchctl procinfo "$pid" 2>/dev/null | grep -E "bundle identifier|executable path|process name" || echo "launchctl procinfo failed for PID $pid"
    done
else
    echo ""
    echo "launchctl procinfo unavailable; skipping bundle identifier lookup."
fi

LOG_PATH="/var/mobile/Library/Preferences/wxkeyboard.log"
if [ -f "$LOG_PATH" ]; then
    echo ""
    echo "==> Tail of $LOG_PATH"
    tail -n 40 "$LOG_PATH"
else
    echo ""
    echo "wxkeyboard log file not found at $LOG_PATH"
fi

echo ""
echo "==> Recent wxkeyboard syslog entries"
if command -v log >/dev/null 2>&1; then
    log show --last 5m --style syslog 2>/dev/null | grep -i wxkeyboard || echo "No wxkeyboard entries in the last 5 minutes."
elif command -v syslog >/dev/null 2>&1; then
    syslog -F '$(Time) $(Sender) $(Message)' 2>/dev/null | grep -i wxkeyboard || echo "No wxkeyboard entries reported by syslog."
else
    echo "No syslog utility (log/syslog) available to query."
fi
