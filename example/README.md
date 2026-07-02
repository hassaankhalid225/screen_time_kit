# screen_time_kit example

A full demo of every `screen_time_kit` feature: permissions, usage stats,
daily/weekly summaries, app limits, and focus mode.

> ⚠️ **Native screen-time APIs require a real device.** Emulators are fine for
> the Android *usage-stats* path, but permission screens and iOS Family Controls
> should be verified on physical hardware. iOS Family Controls does **not** work
> reliably on the Simulator.

## Running

```bash
cd example
flutter run
```

## Manual test checklist

Run each step on a **real device** and confirm the behaviour in the on-screen
log panel.

### 1 · Permission
- **Android:** tap *Request / open settings* → the system **Usage access**
  screen opens → toggle this app on → return → tap *Check status* → shows
  `granted`.
- **iOS (device):** tap *Request / open settings* → Apple's Family Controls
  consent sheet appears → approve → status shows `granted`.

### 2 · Usage stats
- Grant permission first, then tap *Load last 24h*.
- **Android:** a ranked list of apps with minutes appears.
- **iOS:** logs a "not supported" message unless you've added a
  `DeviceActivityReportExtension` target (see the package README).

### 3 · Summaries (pure Dart)
- Tap *Aggregate 7 days* → per-day totals appear. Works wherever step 2 returns
  data; the bucketing itself is platform-independent.

### 4 · App limits
- Tap *Add 1h IG limit* → *Refresh* → the limit appears in the list.
- **Android:** the plugin polls usage; when `com.instagram.android` crosses the
  limit today, the log shows `⛔ Limit reached`. (Set a tiny limit to test
  quickly, or use the focus-mode zero-limit path below.)
- **iOS:** the limit is recorded; enforcement uses `ManagedSettings` shields on
  the app selection (wire `FamilyActivityPicker` in a real integration).
- Tap *Clear all* to remove every limit.

### 5 · Focus mode
- Tap *Start 25m* → applies zero-duration limits to the sample apps. On Android
  you should immediately receive an `onLimitReached` event in the log.
- Tap *Stop* → limits are reverted (or they auto-revert after 25 minutes).

## Android manifest note

`PACKAGE_USAGE_STATS` is merged in from the plugin automatically. To resolve app
names for arbitrary packages on Android 11+, add `QUERY_ALL_PACKAGES` to this
example's `android/app/src/main/AndroidManifest.xml` (see package README).

## iOS capability note

Before running on an iOS device, enable the **Family Controls** capability on the
Runner target and set the deployment target to **iOS 16.0**. See the package
README's *iOS setup* section.
