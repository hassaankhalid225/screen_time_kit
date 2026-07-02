## 0.1.0

Initial release. One Dart API for screen time, app usage, and app limits across
Android and iOS.

### Features
- **Permissions** — unified `PermissionStatus` over Android usage-access
  (`AppOpsManager`) and iOS `FamilyControls` authorization.
- **App usage** — `getAppUsage()` via Android `UsageStatsManager`
  (`queryAndAggregateUsageStats`). iOS reports `PlatformNotSupportedException`
  until a `DeviceActivityReportExtension` is added (documented).
- **App limits** — `setAppLimit` / `removeAppLimit` / `getActiveLimits` /
  `clearAllLimits`. Soft (detect-and-notify) on Android via a usage poller +
  `onLimitReached` stream; natively enforced on iOS via `ManagedSettings`.
- **Summaries** — pure-Dart `getDailySummaries` / `getWeeklySummaries`
  aggregation on top of raw usage.
- **Focus mode** — `startFocusMode` / `stopFocusMode` convenience wrapper with
  automatic timer-based revert.
- Typed exception hierarchy (`ScreenTimeException` and subclasses) mapping every
  native error code.
- Example app demonstrating every feature and integration-test stubs for
  real-device flows.
