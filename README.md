# screen_time_kit

**One Dart API for screen time, app usage, and app limits — Android and iOS, unified.**

[![pub package](https://img.shields.io/pub/v/screen_time_kit.svg)](https://pub.dev/packages/screen_time_kit)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platform](https://img.shields.io/badge/platform-android%20%7C%20ios-lightgrey.svg)](https://pub.dev/packages/screen_time_kit)

---

## Why this package

Today, Flutter developers who want to track app usage or set screen-time limits
have to write **completely separate native integrations for each platform**:
Android's `UsageStatsManager` on one side, Apple's `FamilyControls` /
`DeviceActivity` / `ManagedSettings` frameworks on the other. Every existing
Flutter package in this space is either Android-only or a small, incomplete side
project. **Nothing offers one consistent Dart API across both platforms.**

`screen_time_kit` is that missing unification layer — powering parental-control
apps, focus/productivity apps, and digital-wellbeing dashboards from a single
Dart codebase.

---

## Platform capabilities — read this first

Usage tracking and app blocking behave **very differently** on each platform.
Hiding that would hurt you in production, so here it is up front:

| Capability | Android | iOS |
|---|---|---|
| Permission model | `PACKAGE_USAGE_STATS` — user toggles it on manually in **Settings › Usage access** (no runtime dialog) | `FamilyControls` — Apple's native consent sheet at runtime |
| Read per-app usage | ✅ Full, via `UsageStatsManager` | ⚠️ **Restricted by Apple.** Raw usage is *not* exposed to your app process. Requires a separate `DeviceActivityReportExtension` target (see below). `getAppUsage()` returns `PlatformNotSupportedException` until you add it |
| Resolve app names / icons | ✅ (may need `QUERY_ALL_PACKAGES` on Android 11+) | ⚠️ System returns privacy-scoped display tokens, not names |
| **Enforce** app limits (block the app) | ❌ **No OS API to block third-party apps.** Limits are *soft*: the plugin detects a crossing and fires `onLimitReached`; your app decides what to show | ✅ **Native enforcement** via `ManagedSettings` shields once authorized — a genuine iOS advantage |
| Daily / weekly summaries | ✅ Pure-Dart aggregation on top of usage | ✅ Same (once usage is available) |
| Focus mode | ✅ (soft) | ✅ (enforced) |

> **In one sentence:** Android *sees* everything but can't *block*; iOS *blocks*
> natively but *hides* raw usage behind an extension. This package gives you one
> API over both and is honest about the seams.

---

## Installation

```yaml
dependencies:
  screen_time_kit: ^0.1.0
```

```dart
import 'package:screen_time_kit/screen_time_kit.dart';
```

### Android setup

The plugin already declares `PACKAGE_USAGE_STATS` in its manifest (merged into
your app automatically). To resolve human-readable app names for arbitrary
packages on **Android 11+ (API 30)**, add this to your app's
`android/app/src/main/AndroidManifest.xml` — note it is a Play Store *sensitive*
permission you must justify in your listing:

```xml
<uses-permission
    android:name="android.permission.QUERY_ALL_PACKAGES"
    tools:ignore="QueryAllPackagesPermission" />
```

Without it, `getAppUsage()` still works but falls back to the package name.
`minSdkVersion` must be **21+**.

### iOS setup

iOS requires **iOS 16.0+** and three manual steps in Xcode:

1. **Enable the Family Controls capability.** Open `ios/Runner.xcworkspace` →
   select the *Runner* target → **Signing & Capabilities** → **+ Capability** →
   **Family Controls**.
2. **Set the deployment target to 16.0** (Runner target → *General* → *Minimum
   Deployments*, and in `ios/Podfile`: `platform :ios, '16.0'`).
3. **(For real usage data) add a `DeviceActivityReportExtension` target.** Apple
   does not hand raw usage to your main app for privacy reasons. To display
   usage you add a Device Activity Report extension (File → New → Target →
   *Device Activity Report Extension*), render it inside a SwiftUI
   `DeviceActivityReport` view, and share aggregates through an **App Group**.
   Until you do this, `getAppUsage()` throws `PlatformNotSupportedException` on
   iOS. This is Apple's design, not a limitation of the plugin.

App blocking on iOS also targets apps the user picks via Apple's
`FamilyActivityPicker` (opaque `ApplicationToken`s), not bundle-id strings — wire
the picker in your host app and shield the selection.

---

## Quick start

```dart
import 'package:screen_time_kit/screen_time_kit.dart';

final screenTime = ScreenTimeKit();

// Step 1: Permission
final status = await screenTime.requestPermission();
if (status != PermissionStatus.granted) {
  // show explanation UI, maybe screenTime.openSettings()
}

// Step 2: Usage stats
final usage = await screenTime.getAppUsage(
  since: DateTime.now().subtract(const Duration(days: 1)),
);
for (final app in usage) {
  print('${app.appName}: ${app.usageDuration.inMinutes} min');
}

// Step 3: Set a limit
await screenTime.setAppLimit('com.instagram.android', const Duration(hours: 1));
screenTime.onLimitReached.listen((event) {
  // show your own blocking UI / notification
});

// Step 4: Focus mode
await screenTime.startFocusMode(
  apps: ['com.instagram.android', 'com.tiktok'],
  duration: const Duration(hours: 2),
);
```

---

## iOS App Store distribution ⚠️

Everything above works in **development / debug builds and on your own developer
account with zero extra approval**. However, **shipping a Family Controls app to
the App Store requires Apple's _Family Controls (Distribution)_ entitlement**,
which you must request from Apple and be approved for:

👉 **Request form:** <https://developer.apple.com/contact/request/family-controls-distribution>

Without the distribution entitlement, App Store builds that call the
authorization / shielding APIs will fail — the plugin surfaces this as
`EntitlementMissingException`. Plan for Apple's review time before launch.

---

## API reference

| Member | Returns | Notes |
|---|---|---|
| `checkPermissionStatus()` | `Future<PermissionStatus>` | No prompt |
| `requestPermission()` | `Future<PermissionStatus>` | iOS consent sheet / Android settings screen |
| `openSettings()` | `Future<void>` | Usage-access (Android) / app settings (iOS) |
| `getAppUsage({since, until})` | `Future<List<AppUsageInfo>>` | iOS needs the report extension |
| `setAppLimit(pkg, limit)` | `Future<void>` | Soft on Android, enforced on iOS |
| `removeAppLimit(pkg)` | `Future<void>` | |
| `getActiveLimits()` | `Future<List<AppLimit>>` | |
| `clearAllLimits()` | `Future<void>` | |
| `onLimitReached` | `Stream<AppLimitEvent>` | Fires when an app crosses its limit |
| `getDailySummaries({since, until})` | `Future<List<UsageSummary>>` | Pure-Dart aggregation |
| `getWeeklySummaries({since, until})` | `Future<List<UsageSummary>>` | Monday-start weeks |
| `startFocusMode({apps, duration})` | `Future<void>` | Temporary limits, auto-revert |
| `stopFocusMode()` | `Future<void>` | Revert early |

**Enums / models:** `PermissionStatus` (`granted`, `denied`, `notDetermined`,
`restricted`), `AppUsageInfo`, `AppLimit`, `AppLimitEvent`, `UsageSummary`.

**Exceptions:** all native failures map to typed `ScreenTimeException`
subclasses — `PermissionDeniedException`, `PlatformNotSupportedException`,
`EntitlementMissingException`, `UnknownScreenTimeException`.

---

## Example

See [`example/`](example/) for a full app that demonstrates every feature. It
must be run on a **real device** — native screen-time APIs cannot be meaningfully
exercised on `dart pub publish --dry-run` alone. See
[`example/README.md`](example/README.md) for step-by-step manual test cases.

---

## License

[MIT](LICENSE) © Hassaan
