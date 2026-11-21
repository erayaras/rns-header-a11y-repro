#!/bin/bash
# build-ios.sh [clean] — iOS Release build of this repro for the simulator, headless (xcodebuild; no Simulator window).
#   1. expo prebuild for iOS (with --clean when asked, e.g. after a react-native-screens version change);
#   2. pod install;
#   3. xcodebuild Release for one simulator architecture into build/dd.
# The app ends up in build/dd/Build/Products/Release-iphonesimulator/rnsheadera11yrepro.app.
# DEVICE (default "iPhone 16") names the simulator whose architecture is built; any simulator runs the result.
# A Release build embeds the JS bundle, so a change to App.tsx needs this script again (an incremental build).
# Refuses to start below 11 GiB of free disk or with kern.memorystatus_level < 35 (a guard for a busy Mac).
set -u
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
MODE=${1:-}
DEVICE=${DEVICE:-iPhone 16}
R=$(cd "$(dirname "$0")/.." && pwd)
cd "$R" || exit 2
FREE=$(df -g "$R" | awk 'NR==2{print $4}')
LEVEL=$(sysctl -n kern.memorystatus_level)
SCREENS=$(node -p "require('react-native-screens/package.json').version")
echo "start=$(date +%H:%M:%S) free_gb=$FREE mem_level=$LEVEL screens=$SCREENS device=$DEVICE mode=${MODE:-incremental}"
[ "$FREE" -ge 11 ] || { echo "disk below 11 GiB"; exit 3; }
[ "$LEVEL" -ge 35 ] || { echo "memory level below 35"; exit 3; }
PREBUILD=(npx expo prebuild --platform ios --no-install)
[ "$MODE" = clean ] && PREBUILD+=(--clean)
CI=1 "${PREBUILD[@]}" || { echo "prebuild failed"; exit 4; }
(cd ios && pod install) || { echo "pod install failed"; exit 4; }
echo "pod: $(grep -m1 -E '^  - RNScreens \(' ios/Podfile.lock)"
WS=$(ls -d ios/*.xcworkspace | head -1)
SCHEME=$(basename "$WS" .xcworkspace)
CI=1 RCT_NO_LAUNCH_PACKAGER=true xcodebuild -workspace "$WS" -scheme "$SCHEME" -configuration Release \
  -sdk iphonesimulator -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$R/build/dd" \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build < /dev/null
rc=$?
echo "end=$(date +%H:%M:%S) xcodebuild_rc=$rc screens=$SCREENS app=$(ls -d "$R"/build/dd/Build/Products/Release-iphonesimulator/*.app 2>/dev/null | head -1)"
exit $rc
