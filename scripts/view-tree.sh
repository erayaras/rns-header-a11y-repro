#!/bin/bash
# view-tree.sh UDID OUTFILE — attaches lldb to the running repro app for a moment and writes the key window's view tree
# in pre-order, one line per view: depth, class<address>, frame, and the accessibilityContainer when it is set.
# Comparing two dumps shows where Fabric's recycle pool put a view (same address, new place). Nothing in the app is changed.
set -u
UDID=${1:?udid}
F=${2:?outfile}
BID=com.example.rnsheadera11yrepro
pid=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | awk -v p="$BID" 'index($0, p) {print $1; exit}')
[ -n "$pid" ] && [ "$pid" != "-" ] || { echo "no $BID process"; exit 1; }
timeout 120 lldb -p "$pid" --batch \
  -o 'expr -l objc -- @import UIKit' \
  -o 'expr -l objc -O -- NSMutableString *treeOut = [NSMutableString string]; NSMutableArray *treeStack = [NSMutableArray array]; NSMutableArray *treeDepths = [NSMutableArray array]; for (UIWindow *treeWin in [[(NSArray *)[[UIApplication sharedApplication] windows] reverseObjectEnumerator] allObjects]) { [treeStack addObject:treeWin]; [treeDepths addObject:@0]; } while ([treeStack count] > 0) { UIView *treeView = (UIView *)[treeStack lastObject]; [treeStack removeLastObject]; NSInteger treeDepth = [(NSNumber *)[treeDepths lastObject] integerValue]; [treeDepths removeLastObject]; id treeContainer = (id)[(NSObject *)treeView accessibilityContainer]; [treeOut appendFormat:@"%ld %@<%p> frame=%@%@\n", (long)treeDepth, NSStringFromClass((Class)object_getClass(treeView)), treeView, NSStringFromCGRect([treeView frame]), treeContainer ? [NSString stringWithFormat:@" container=%@<%p>", NSStringFromClass((Class)object_getClass(treeContainer)), treeContainer] : @""]; for (UIView *treeSub in [[(NSArray *)[treeView subviews] reverseObjectEnumerator] allObjects]) { [treeStack addObject:treeSub]; [treeDepths addObject:@(treeDepth + 1)]; } } treeOut' \
  -o 'detach' > "$F" 2>&1
rc=$?
echo "lldb pid=$pid rc=$rc views=$(grep -cE '^[0-9]+ ' "$F")"
