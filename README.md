# react-native-screens: recycled header item keeps `UINavigationBar` as its `accessibilityContainer` (iOS, Fabric)

Minimal reproduction for a main-thread hang (100% CPU) in UIKit's accessibility walk after a native-stack navigator with a custom header item is unmounted and mounted again with one extra full-screen `View` above it.

## Result

**It hangs** whenever the remount adds a full-screen `View` above the navigator that the first mount did not have (`-wrapper alternate`), on react-native-screens 4.30.0, 4.30.1 and 4.31.0-nightly-20261120-83408f21c. Measured on the iOS 27.0 simulator (iPhone 17 Pro), Release build; one run per shape: an accessibility query (`maestro hierarchy`, 120 s cap), then up to three remounts, each followed by the same query.

| Shape (`-remount` / `-wrapper`) | 4.30.0 | 4.30.1 | 4.31.0-nightly-20261120 |
|---|---|---|---|
| `same` / `none` | no hang | no hang | no hang |
| `gap` / `none` | no hang | no hang | no hang |
| `interlude` / `none` | no hang | no hang | no hang |
| `same` / `view` | no hang | no hang | no hang |
| `gap` / `view` | no hang | no hang | no hang |
| `interlude` / `view` | no hang | no hang | no hang |
| `same` / `alternate` | **hang** | **hang** | **hang** |
| `gap` / `alternate` | **hang** | **hang** | **hang** |
| `interlude` / `alternate` | **hang** | **hang** | **hang** |

The 4.30.0 `none` / `view` rows come from an earlier build of the same `App.tsx` before the `alternate` option was added (the code those shapes run is unchanged). "no hang": the first query and all three post-remount queries returned (11–46 s each, mostly the XCTest driver's own time), the app's CPU 0%. "hang": the first query returned; the query after the first remount timed out at 120 s while the app's process stayed at 94–100% CPU, a 5 s `sample` of it sits in `-[UINavigationBarAccessibility accessibilityElements]` → `_accessibilityFindAncestor`, and `[bar accessibilityElements]` asked through lldb did not return within 30 s. In every hung run (where the lldb listing completed: 7 of 9) one `RCTViewComponentView` outside the bar names the bar as its `accessibilityContainer`: the same object (same address) that was the header `Pressable` before the remount, now the 402 × 874 wrapper under `RNCSafeAreaProviderComponentView`. After the first query on a fresh launch no run (22 of 22) had such a view.

## What happens

1. The screen's `headerRight` is a `Pressable` (an `RCTViewComponentView`) inside an `RNSScreenStackHeaderSubview`. After the first accessibility query that view's `accessibilityContainer` is the `RNSNavigationBar` (UIKit sets it on the elements the bar vends).
2. **Remount** unmounts the navigator. Fabric gives the header `Pressable` back to its recycle pool (LIFO, per component type); `prepareForRecycle` does not clear `accessibilityContainer`. The header subview itself is not recycled, but its child is. In the first mount the navigator has no plain-`View` ancestor, so the header `Pressable` is the last `RCTViewComponentView` deleted and sits on top of the pool.
3. The new tree has a full-screen `View` above the navigator (`-wrapper alternate`: present on odd generations only). It is the first `RCTViewComponentView` created, so it takes the header `Pressable` from the pool. The `RNSScreenStackView` is recycled too and keeps its `UINavigationController` and its bar, so the new wrapper's `accessibilityContainer` is the very bar it now contains.
4. The next accessibility query: `-[UINavigationBarAccessibility accessibilityElements]` → `_accessibilityFindAncestor` walks `RNSNavigationBar → UILayoutContainerView → RNSScreenStackView → RCTViewComponentView (wrapper) → RNSNavigationBar → …` and never returns. The main thread stays at 100%; XCTest/Maestro tree requests time out, and any client that asks the bar for its elements (VoiceOver uses the same call) hangs the app.

When the wrapper is there on every mount (`-wrapper view`) or never (`-wrapper none`), the view trees (`scripts/view-tree.sh`) show the pool handing the old wrapper to the new wrapper and swapping the header `Pressable` with the content's **Remount** `Pressable` on each remount, so no view that names the bar becomes the bar's ancestor and nothing hangs. The order follows from Fabric's mutation order (a removed subtree's descendants are deleted before its root; a new subtree's root is created before its descendants) and the LIFO pool in `RCTComponentViewRegistry`.

## Versions

- expo 58.0.19, react-native 0.88.0 (New Architecture, prebuilt core); `overrides` in `package.json` pin the expo / @expo / @react-native packages to one consistent SDK 58 set (a newer `expo-modules-core` crashed at launch on react-native 0.88.0)
- react-native-screens: see Result
- react-native-safe-area-context 5.10.1
- @react-navigation/native 7.5.2, @react-navigation/native-stack 7.21.1
- Xcode 27.2, iOS 27.0 simulator (iPhone 17 Pro), Release build

## The app

`App.tsx` is the whole app: one native-stack screen whose `headerTitle` and `headerRight` are React elements, inside a `SafeAreaProvider`. The `NavigationContainer` has a `key`; tapping **Remount** (or opening `rnsrepro://remount`) changes it, which unmounts and mounts the navigator again. iOS launch arguments choose the shape:

| Argument | Values |
|---|---|
| `-remount` | `same` (key change in one commit, default), `gap` (one commit with no navigator, then the new one), `interlude` (a plain screen for 1 s, then the new one) |
| `-wrapper` | `none` (default), `view` (a full-screen `View`, `collapsable={false}`, around the navigator on every mount), `alternate` (that `View` on odd generations only: the first remount adds it) |

## Steps

```bash
npm install
scripts/build-ios.sh            # expo prebuild + pod install + xcodebuild Release into build/dd (no Simulator window)
xcrun simctl boot <UDID>        # any iOS simulator
```

By hand:

1. `xcrun simctl install <UDID> build/dd/Build/Products/Release-iphonesimulator/rnsheadera11yrepro.app`
2. `xcrun simctl launch <UDID> com.example.rnsheadera11yrepro -remount same -wrapper alternate`
3. Make one accessibility query of the screen: `maestro --udid <UDID> hierarchy` (Maestro), an XCUITest that reads the element tree, or Accessibility Inspector. It returns.
4. Tap **Remount** (or `xcrun simctl openurl <UDID> rnsrepro://remount`).
5. Make the same query again. It does not return; the app's process stays at ~100% CPU.

Scripted (Maestro, lldb and `timeout` needed): `scripts/run-shapes.sh <UDID> <OUTDIR> <TAG> [same-alternate …]` runs `scripts/measure.sh` per shape: launch, query 1, the lldb listing of every view whose `accessibilityContainer` is a navigation bar (`scripts/bar-elements.sh`: INSIDE the bar or STALE outside it) and the view tree (`scripts/view-tree.sh`), then up to three remounts, each followed by the query, CPU and the listings; a query that times out (120 s) adds two CPU readings and a 5 s `sample` of the process and ends the run.
