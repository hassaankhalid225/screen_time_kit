# Master Build Spec — `screen_time_kit`

> **Purpose of this document:** This is a complete implementation spec for a Flutter **plugin** package (native Android + iOS code required) meant to be built by an AI coding assistant (Cursor). Follow every section in order. This is more complex than a pure-Dart package because it requires native Kotlin (Android) and Swift (iOS) code behind platform channels — read Section 4 carefully before writing any Dart code.

---

## 1. What We're Building

A **unified, cross-platform screen time and app usage SDK for Flutter**. Today, Flutter developers who want to track app usage or set screen time limits have to write completely separate native integrations for each platform: Android's `UsageStatsManager` on one side, Apple's `FamilyControls` / `DeviceActivity` / `ManagedSettings` frameworks on the other. Every existing Flutter package in this space is either Android-only or a small, incomplete side project. Nothing offers one consistent Dart API across both platforms.

This package is that missing unification layer — powering parental control apps, focus/productivity apps, and digital wellbeing dashboards from a single Dart codebase.

**Package name:** `screen_time_kit`
**Tagline for README:** "One Dart API for screen time, app usage, and app limits — Android and iOS, unified."

---

## 2. Goals & Non-Goals

**Goals (v1 — free to build and test):**
- A single, consistent Dart API that works identically whether the app runs on Android or iOS
- Android implementation via `UsageStatsManager` (no special approval needed — only a user-granted permission)
- iOS implementation via `FamilyControls`, `DeviceActivity`, and `ManagedSettings` frameworks (works fully in development/debug builds and on your own developer account with zero extra approval; only **App Store distribution** requires Apple's Family Controls Distribution Entitlement request — this package must document that clearly, not hide it)
- Clean plugin architecture using `pigeon` or standard `MethodChannel` for type-safe platform communication

**Non-Goals (explicitly out of scope for v1):**
- No cloud backend / sync — this package only reads/writes on-device data. Sync across family devices is left to the host app.
- No website/URL-level content filtering in v1 — app-level limits only
- No location tracking or any feature unrelated to screen time/app usage

---

## 3. Tech Stack & Dependencies

```yaml
name: screen_time_kit
description: A unified Dart API for screen time tracking, app usage stats, and app limits across Android (UsageStatsManager) and iOS (Family Controls / DeviceActivity).
version: 0.1.0
homepage: <your github repo url>
repository: <your github repo url>
issue_tracker: <your github issues url>

environment:
  sdk: '>=3.4.0 <4.0.0'
  flutter: '>=3.22.0'

dependencies:
  flutter:
    sdk: flutter
  plugin_platform_interface: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  pigeon: ^22.0.0    # for type-safe platform channel code generation
```

**Native requirements:**
- Android: `minSdkVersion 21+`, uses `android.permission.PACKAGE_USAGE_STATS` (a special user-granted permission via Settings, not a runtime permission dialog)
- iOS: `iOS 16.0+` minimum (Family Controls / DeviceActivity require iOS 15/16+), requires the `Family Controls` capability enabled in Xcode

---

## 4. Plugin Architecture — Read Before Writing Any Code

This is a **federated plugin** structure, following Flutter's official plugin conventions:

```
screen_time_kit/                    # app-facing package (pure Dart, public API)
screen_time_kit_platform_interface/ # abstract interface + method channel default impl
screen_time_kit_android/            # Android implementation (Kotlin)
screen_time_kit_ios/                # iOS implementation (Swift)
```

For v0.1, it's acceptable to build this as a **single non-federated plugin** (simpler) with `android/` and `ios/` folders directly inside `screen_time_kit/` — federate later if the package grows. Use this simpler structure unless told otherwise:

```
screen_time_kit/
├── lib/
│   ├── screen_time_kit.dart              # public exports
│   └── src/
│       ├── screen_time_kit_platform_interface.dart
│       ├── screen_time_kit_method_channel.dart
│       ├── models/
│       │   ├── app_usage_info.dart
│       │   ├── app_limit.dart
│       │   └── permission_status.dart
│       └── exceptions/
│           └── screen_time_exceptions.dart
├── android/
│   └── src/main/kotlin/.../ScreenTimeKitPlugin.kt
├── ios/
│   └── Classes/ScreenTimeKitPlugin.swift
├── example/
│   └── lib/main.dart
├── test/
│   └── screen_time_kit_test.dart
├── CHANGELOG.md
├── README.md
├── LICENSE
└── pubspec.yaml
```

---

## 5. Feature List — Build in This Order

### 5.1 Platform Interface & Method Channel Setup
- Define `ScreenTimeKitPlatform` abstract class (the platform interface pattern) with method signatures for every feature below
- Implement `MethodChannelScreenTimeKit` as the default implementation using `MethodChannel('screen_time_kit')`
- Every platform call must be wrapped so native exceptions map to typed Dart exceptions (`PermissionDeniedException`, `PlatformNotSupportedException`, `EntitlementMissingException` for iOS)

### 5.2 Permission Handling — `requestPermission()` / `checkPermissionStatus()`
- **Android side (Kotlin):** `PACKAGE_USAGE_STATS` isn't a runtime permission — it requires opening `Settings.ACTION_USAGE_ACCESS_SETTINGS` and having the user manually toggle it on. Implement `openUsageAccessSettings()` to launch this screen, and `hasUsageAccessPermission()` to check current status (via `AppOpsManager`).
- **iOS side (Swift):** Use `AuthorizationCenter.shared.requestAuthorization(for: .individual)` from the `FamilyControls` framework. This shows Apple's native consent screen. Handle the async authorization result and map to the same `PermissionStatus` enum used on Android.
- Dart-side: `Future<PermissionStatus> requestPermission()` returns a unified enum: `granted`, `denied`, `notDetermined`, `restricted`.

### 5.3 App Usage Stats — `getAppUsage()`
- **Android (Kotlin):** Query `UsageStatsManager.queryUsageStats()` with `INTERVAL_DAILY` or a custom time range, aggregate by package name, resolve app names/icons via `PackageManager`.
- **iOS (Swift):** This is the trickiest part — Apple's `DeviceActivityReport` extension architecture doesn't expose raw usage data directly to the main app process for privacy reasons. Research and implement using `DeviceActivityCenter` + a `DeviceActivityReportExtension` target, passing aggregated (non-identifying where required) data back via an App Group shared container. **Flag this to the user clearly in code comments**: iOS usage data access is intentionally more restricted than Android by Apple's design, and the extension setup requires an additional Xcode target — document this setup step thoroughly in the README.
- Dart-side model: `AppUsageInfo { String packageName; String appName; Duration usageDuration; DateTime date; }`

### 5.4 App Limits — `setAppLimit()` / `removeAppLimit()`
- **Android (Kotlin):** No native OS-level app-blocking API exists on Android for third-party apps. Implement this as a **soft limit**: track usage in the background (via a foreground service or periodic `WorkManager` job) and fire a Dart-side callback/notification when the limit is reached — the host app then decides what UI to show (e.g., an overlay). Document this limitation clearly — this package cannot force-close another app on Android; it can only detect and notify.
- **iOS (Swift):** Use `ManagedSettings` framework's `ManagedSettingsStore` to apply `application(_:).blockedApplications` — iOS *can* natively enforce app blocking (via `Shield` API) once the user has granted Family Controls authorization. This is a genuine advantage on iOS and should be highlighted in the README.
- Dart-side: `Future<void> setAppLimit(String packageName, Duration limit)`, exposing a `Stream<AppLimitEvent> onLimitReached`.

### 5.5 Daily/Weekly Summary Aggregation
- Pure-Dart aggregation layer on top of 5.3's raw data — group by day/week, compute totals per app and total device usage
- No native code needed here — build entirely on top of `getAppUsage()` results

### 5.6 Focus Mode — `startFocusMode()` / `stopFocusMode()`
- Convenience wrapper: temporarily apply limits (via 5.4) to a list of "distracting" apps for a set duration, auto-reverting when the timer ends
- Pure Dart orchestration on top of 5.4 — no new native code required

---

## 6. Public API — Target Usage Example

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

## 7. Testing Requirements

- Unit test the platform-interface layer and Dart-side aggregation logic (5.5, 5.6) with a `MockScreenTimeKitPlatform` — these don't need real devices
- Native code (Kotlin/Swift) is hard to unit test in CI; instead, the `example/` app must be a manually-testable demo covering every feature — document manual test steps in `example/README.md`
- Add integration test stubs (`integration_test` package) for the permission flow and usage stats flow, marked clearly as requiring a real device to run

---

## 8. Documentation Requirements (for pub.dev score)

1. **README.md** must include, in this order:
   - One-line description + badges
   - "Why this package" — explain the fragmentation problem (Android-only packages, no unified API) directly
   - **A clearly highlighted "Platform Capabilities" comparison table** showing what's possible on Android vs iOS (this is critical — usage tracking and blocking behave very differently per platform, and hiding this would hurt trust)
   - Installation + native setup steps for BOTH platforms (Android manifest permission declaration, iOS Family Controls capability + entitlement setup, iOS DeviceActivityReportExtension target setup)
   - Quick start code (Section 6 example)
   - **A dedicated "iOS App Store Distribution" section** explaining that shipping to the App Store requires requesting Apple's Family Controls Distribution Entitlement, with a link to Apple's request form
   - Full API reference table
   - License
2. Dartdoc comments on every public Dart class/method
3. CHANGELOG.md starting at `0.1.0`
4. `example/` app that demonstrates every feature end-to-end on a real device (native plugins can't be meaningfully demoed on `dart pub publish --dry-run` alone — emphasize real-device testing in the example README)

---

## 9. Publishing Checklist

1. Run `flutter analyze` on both the package and `example/` — zero warnings
2. Run `dart format .`
3. Run `flutter test`
4. Manually test the `example/` app on a real Android device (emulator is fine for usage stats, but permission screens should be verified) and a real iOS device (Family Controls generally does not work reliably on iOS Simulator — note this in docs)
5. Run `dart pub publish --dry-run` — fix all warnings, pay special attention to plugin-specific pubspec fields (`flutter.plugin.platforms`)
6. Verify `LICENSE` exists
7. Push to GitHub, tag `v0.1.0`, then `dart pub publish`

---

## 10. Instructions for the AI Coding Assistant (Cursor)

- This is a **plugin package**, not a pure-Dart package — do not skip the native Kotlin/Swift implementation and try to fake it with placeholder Dart-only code
- Build the platform interface (5.1) and Android implementation (5.2–5.4, Android side) fully first, since Android has fewer native restrictions and is faster to iterate on
- Only move to the iOS implementation once the Android path works end-to-end in the example app
- For iOS, research current `FamilyControls`/`DeviceActivity`/`ManagedSettings` API signatures directly from Apple's current documentation before writing Swift code — these are relatively new frameworks (introduced iOS 15/16) and Apple has iterated on the APIs since
- Be explicit and honest in code comments and README about platform limitations (Section 5.4) — do not overstate what Android can do, and do not understate the extra Xcode/entitlement setup iOS requires
- After each feature module in Section 5, update the `example/` app to demonstrate it before moving to the next module
- Use `flutter_lints` recommended rules for the Dart code; follow standard Kotlin/Swift style conventions for native code
