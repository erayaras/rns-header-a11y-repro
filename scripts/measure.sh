#!/bin/bash
# measure.sh UDID OUTDIR [REMOUNTS] — one run of the repro on a booted iOS simulator, headless:
#   install build/dd/.../rnsheadera11yrepro.app, launch it with LAUNCH_ARGS (e.g. "-remount same -wrapper alternate"),
#   query 1 (`maestro hierarchy`, an XCTest accessibility tree request, 120 s cap), the lldb bar listing (bar-elements.sh)
#   and view tree (view-tree.sh), then REMOUNTS times (default 3): tap "Remount" (Maestro), screenshot, the same query,
#   process CPU, the bar listing and the view tree.
#   A query that fails or times out is followed by two CPU readings, a 5 s `sample` of the process and the bar listing, and
#   ends the run (the app is hung; later taps cannot reach it). The app is terminated at the end.
# Needs Maestro (MAESTRO, default ~/.maestro/bin/maestro), lldb and `timeout`. Output files go to OUTDIR.
set -u
UDID=${1:?udid}
O=${2:?outdir}
REMOUNTS=${3:-3}
S=$(cd "$(dirname "$0")" && pwd)
R=$(dirname "$S")
BID=com.example.rnsheadera11yrepro
M=${MAESTRO:-$HOME/.maestro/bin/maestro}
mkdir -p "$O"
APPDIR=$R/build/dd/Build/Products/Release-iphonesimulator/rnsheadera11yrepro.app
[ -d "$APPDIR" ] || { echo "no built app at $APPDIR"; exit 2; }
echo "start=$(date +%H:%M:%S) udid=$UDID screens_pod=\"$(grep -m1 -E '^  - RNScreens \(' "$R/ios/Podfile.lock" | sed 's/^ *- //')\" app_mtime=\"$(stat -f %Sm "$APPDIR/main.jsbundle")\""
trap 'xcrun simctl terminate "$UDID" "$BID" > /dev/null 2>&1' EXIT
xcrun simctl install "$UDID" "$APPDIR" || exit 4
xcrun simctl terminate "$UDID" "$BID" > /dev/null 2>&1
# LAUNCH_ARGS reach the app through Settings (the NSUserDefaults argument domain).
# shellcheck disable=SC2086
xcrun simctl launch "$UDID" "$BID" ${LAUNCH_ARGS:-} > "$O/launch.txt" 2>&1 || exit 4
echo "launch args: ${LAUNCH_ARGS:-none}"
sleep 6
xcrun simctl io "$UDID" screenshot "$O/0-launch.png" > /dev/null 2>&1
apppid() { xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | awk -v p="$BID" 'index($0, p) {print $1; exit}'; }
query() { # query NAME; returns the hierarchy exit code
  local start rc pid
  start=$(date +%s)
  timeout 120 "$M" --udid "$UDID" hierarchy > "$O/$1-hierarchy.json" 2> "$O/$1-hierarchy.err"
  rc=$?
  pid=$(apppid)
  echo "$1 hierarchy rc=$rc seconds=$(( $(date +%s) - start )) bytes=$(wc -c < "$O/$1-hierarchy.json" | tr -d ' ') pid=$pid cpu=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ')"
  if [ "$rc" != 0 ] && [ -n "$pid" ]; then
    sleep 5
    CPU_AGAIN=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ')
    echo "$1 cpu_again=$CPU_AGAIN"
    sample "$pid" 5 -file "$O/$1-sample.txt" > /dev/null 2>&1
    echo "$1 sample _accessibilityFindAncestor lines=$(grep -c -- '_accessibilityFindAncestor' "$O/$1-sample.txt")"
  fi
  return "$rc"
}
CPU_AGAIN=
query q1
q=$?
"$S/bar-elements.sh" "$UDID" "$O/q1-bar.txt"
"$S/view-tree.sh" "$UDID" "$O/q1-tree.txt"
i=1
while [ "$q" = 0 ] && [ "$i" -le "$REMOUNTS" ]; do
  timeout 120 "$M" --udid "$UDID" test "$S/remount.yaml" > "$O/r$i-tap.txt" 2>&1
  echo "r$i tap rc=$?"
  sleep 3
  xcrun simctl io "$UDID" screenshot "$O/r$i.png" > /dev/null 2>&1
  query "r$i"
  q=$?
  "$S/bar-elements.sh" "$UDID" "$O/r$i-bar.txt"
  "$S/view-tree.sh" "$UDID" "$O/r$i-tree.txt"
  i=$((i + 1))
done
# A failed query is the hang only when the app's process is busy (>= 90% CPU) after it; a failed query with an idle
# process is a tooling failure (e.g. the XCTest driver dropping the connection) and leaves the shape unmeasured.
if [ "$q" = 0 ]; then
  echo "result=no-hang"
elif [ "${CPU_AGAIN%%.*}" -ge 90 ] 2>/dev/null; then
  echo "result=HANG"
else
  echo "result=query-failed-app-idle"
fi
echo "end=$(date +%H:%M:%S)"
