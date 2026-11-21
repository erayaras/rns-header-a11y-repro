#!/bin/bash
# bar-elements.sh UDID OUTFILE — attaches lldb to the running repro app for a moment (nothing in the app is changed):
#   1. lists every view whose accessibilityContainer is a UINavigationBar: INSIDE when the view is a descendant of that
#      bar, STALE when it is not (a recycled header child), with class, address, frame and superview;
#   2. asks each navigation bar for accessibilityElements (the call UIKit's accessibility clients make) with a 30 s timeout.
# Needs the app's process on the simulator UDID; lldb attaches to it from the host (Xcode command line tools).
set -u
UDID=${1:?udid}
F=${2:?outfile}
BID=com.example.rnsheadera11yrepro
pid=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | awk -v p="$BID" 'index($0, p) {print $1; exit}')
[ -n "$pid" ] && [ "$pid" != "-" ] || { echo "no $BID process"; exit 1; }
timeout 240 lldb -p "$pid" --batch \
  -o 'expr -l objc -- @import UIKit' \
  -o 'expr -l objc -O -- NSMutableArray *s = [NSMutableArray arrayWithArray:(NSArray *)[[UIApplication sharedApplication] windows]]; NSMutableString *r = [NSMutableString string]; while ([s count] > 0) { UIView *v = (UIView *)[s lastObject]; [s removeLastObject]; id c = (id)[(NSObject *)v accessibilityContainer]; if (c != nil && (BOOL)[(NSObject *)c isKindOfClass:[UINavigationBar class]]) { [r appendFormat:@"%@ %@<%p> frame=%@ superview=%@<%p> container=%@<%p>\n", ((BOOL)[v isDescendantOfView:(UIView *)c]) ? @"INSIDE" : @"STALE", NSStringFromClass((Class)object_getClass(v)), v, NSStringFromCGRect([v frame]), NSStringFromClass((Class)object_getClass([v superview])), [v superview], NSStringFromClass((Class)object_getClass(c)), c]; } [s addObjectsFromArray:(NSArray *)[v subviews]]; } r' \
  -o 'script import time; print("ELEMENTS_START", time.time())' \
  -o 'expr -t 30000000 -u true -l objc -O -- NSMutableString *r = [NSMutableString string]; NSMutableArray *s = [NSMutableArray arrayWithArray:(NSArray *)[[UIApplication sharedApplication] windows]]; while ([s count] > 0) { UIView *v = (UIView *)[s lastObject]; [s removeLastObject]; if ((BOOL)[v isKindOfClass:[UINavigationBar class]]) { NSArray *e = (NSArray *)[(NSObject *)v accessibilityElements]; [r appendFormat:@"ELEMENTS %@<%p> count=%lu\n", NSStringFromClass((Class)object_getClass(v)), v, (unsigned long)[e count]]; } [s addObjectsFromArray:(NSArray *)[v subviews]]; } r' \
  -o 'script import time; print("ELEMENTS_END", time.time())' \
  -o 'detach' > "$F" 2>&1
rc=$?
echo "lldb pid=$pid rc=$rc"
grep -E "^(INSIDE|STALE|ELEMENTS)|timed out|interrupted|error:" "$F" | cut -c1-260
