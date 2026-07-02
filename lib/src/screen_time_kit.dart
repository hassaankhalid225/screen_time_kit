import 'dart:async';

import 'models/app_limit.dart';
import 'models/app_usage_info.dart';
import 'models/permission_status.dart';
import 'models/usage_summary.dart';
import 'screen_time_kit_platform_interface.dart';

/// The entry point of the plugin: one Dart API for screen time, app usage, and
/// app limits across Android and iOS.
///
/// ```dart
/// final screenTime = ScreenTimeKit();
/// if ((await screenTime.requestPermission()).isGranted) {
///   final usage = await screenTime.getAppUsage(
///     since: DateTime.now().subtract(const Duration(days: 1)),
///   );
/// }
/// ```
///
/// Platform-specific behaviour (especially for app limits) is documented on the
/// individual methods and in the README's capability table — read it before
/// assuming a feature behaves identically on both platforms.
class ScreenTimeKit {
  /// Creates a [ScreenTimeKit] that talks to the current platform.
  ScreenTimeKit();

  ScreenTimeKitPlatform get _platform => ScreenTimeKitPlatform.instance;

  final Map<String, Timer> _focusTimers = <String, Timer>{};

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  /// Returns the underlying OS version string (useful for bug reports).
  Future<String?> getPlatformVersion() => _platform.getPlatformVersion();

  // ---------------------------------------------------------------------------
  // 5.2 Permissions
  // ---------------------------------------------------------------------------

  /// Returns the current authorization state without prompting the user.
  Future<PermissionStatus> checkPermissionStatus() =>
      _platform.checkPermissionStatus();

  /// Requests authorization and returns the resulting [PermissionStatus].
  ///
  /// * iOS: shows Apple's Family Controls consent sheet.
  /// * Android: opens the system *Usage access* settings screen (there is no
  ///   runtime dialog for `PACKAGE_USAGE_STATS`) and reports status afterwards.
  Future<PermissionStatus> requestPermission() => _platform.requestPermission();

  /// Opens the relevant platform settings screen (Usage access on Android, the
  /// app settings page on iOS). Use this from an "open settings" button when the
  /// user previously denied access.
  Future<void> openSettings() => _platform.openSettings();

  // ---------------------------------------------------------------------------
  // 5.3 App usage stats
  // ---------------------------------------------------------------------------

  /// Returns aggregated per-app foreground usage between [since] and [until].
  ///
  /// [until] defaults to `DateTime.now()`. Throws a [PermissionDeniedException]
  /// if usage access has not been granted.
  ///
  /// > **iOS note:** Apple does not expose raw per-app usage to the host process
  /// > the way Android does; iOS usage requires a `DeviceActivityReport`
  /// > extension and returns privacy-scoped data. See the README.
  Future<List<AppUsageInfo>> getAppUsage({
    required DateTime since,
    DateTime? until,
  }) {
    return _platform.getAppUsage(start: since, end: until ?? DateTime.now());
  }

  // ---------------------------------------------------------------------------
  // 5.4 App limits
  // ---------------------------------------------------------------------------

  /// Configures a daily [limit] for [packageName].
  ///
  /// * iOS enforces this natively (the app is shielded once the limit is hit).
  /// * Android tracks usage and emits an [AppLimitEvent] on [onLimitReached]
  ///   when the limit is crossed — it cannot force-close the app itself.
  Future<void> setAppLimit(String packageName, Duration limit) =>
      _platform.setAppLimit(packageName, limit);

  /// Removes any limit configured for [packageName].
  Future<void> removeAppLimit(String packageName) =>
      _platform.removeAppLimit(packageName);

  /// Returns all currently configured limits.
  Future<List<AppLimit>> getActiveLimits() => _platform.getActiveLimits();

  /// Removes every configured limit.
  Future<void> clearAllLimits() => _platform.clearAllLimits();

  /// Fires whenever an app crosses its configured limit.
  Stream<AppLimitEvent> get onLimitReached => _platform.onLimitReached;

  // ---------------------------------------------------------------------------
  // 5.5 Summary aggregation (pure Dart, on top of getAppUsage)
  // ---------------------------------------------------------------------------

  /// Groups usage between [since] and [until] into per-day [UsageSummary]s.
  ///
  /// This performs no native work beyond a single [getAppUsage] call; the
  /// bucketing happens in Dart, so it behaves identically on every platform.
  Future<List<UsageSummary>> getDailySummaries({
    required DateTime since,
    DateTime? until,
  }) async {
    final end = until ?? DateTime.now();
    final usage = await getAppUsage(since: since, until: end);
    return aggregateUsage(usage, bucket: SummaryBucket.daily);
  }

  /// Groups usage between [since] and [until] into per-week [UsageSummary]s
  /// (weeks start on Monday).
  Future<List<UsageSummary>> getWeeklySummaries({
    required DateTime since,
    DateTime? until,
  }) async {
    final end = until ?? DateTime.now();
    final usage = await getAppUsage(since: since, until: end);
    return aggregateUsage(usage, bucket: SummaryBucket.weekly);
  }

  // ---------------------------------------------------------------------------
  // 5.6 Focus mode (pure Dart orchestration on top of limits)
  // ---------------------------------------------------------------------------

  /// Temporarily limits a set of distracting [apps] for [duration].
  ///
  /// Each app is given a zero-duration limit (effectively "blocked") for the
  /// window, then automatically reverted when the timer elapses or when
  /// [stopFocusMode] is called. On Android, "blocked" means you will receive an
  /// immediate [onLimitReached] event to act on; on iOS the app is shielded.
  Future<void> startFocusMode({
    required List<String> apps,
    required Duration duration,
  }) async {
    for (final app in apps) {
      await setAppLimit(app, Duration.zero);
      _focusTimers[app]?.cancel();
      _focusTimers[app] = Timer(duration, () {
        // Fire-and-forget revert; errors are swallowed because the timer has no
        // caller to surface them to.
        unawaited(removeAppLimit(app).catchError((_) {}));
        _focusTimers.remove(app);
      });
    }
  }

  /// Ends focus mode early, reverting every limit applied by [startFocusMode].
  Future<void> stopFocusMode() async {
    final apps = _focusTimers.keys.toList(growable: false);
    for (final app in apps) {
      _focusTimers.remove(app)?.cancel();
      await removeAppLimit(app);
    }
  }

  /// Whether a focus session is currently active.
  bool get isFocusModeActive => _focusTimers.isNotEmpty;

  /// Releases resources held by this instance. Call from your widget's
  /// `dispose` if you started a focus session.
  void dispose() {
    for (final timer in _focusTimers.values) {
      timer.cancel();
    }
    _focusTimers.clear();
  }
}

/// The bucket granularity used by [aggregateUsage].
enum SummaryBucket {
  /// One [UsageSummary] per calendar day.
  daily,

  /// One [UsageSummary] per ISO week (Monday-start).
  weekly,
}

/// Buckets a flat list of [AppUsageInfo] into ordered [UsageSummary]s.
///
/// Exposed (and pure) so it can be unit-tested without any platform channel.
List<UsageSummary> aggregateUsage(
  List<AppUsageInfo> usage, {
  required SummaryBucket bucket,
}) {
  final buckets = <DateTime, Map<String, Duration>>{};

  for (final info in usage) {
    final key = _bucketStart(info.date, bucket);
    final perApp = buckets.putIfAbsent(key, () => <String, Duration>{});
    perApp.update(
      info.packageName,
      (existing) => existing + info.usageDuration,
      ifAbsent: () => info.usageDuration,
    );
  }

  final keys = buckets.keys.toList()..sort();
  return keys.map((start) {
    final end = bucket == SummaryBucket.daily
        ? start.add(const Duration(days: 1))
        : start.add(const Duration(days: 7));
    return UsageSummary(start: start, end: end, perApp: buckets[start]!);
  }).toList(growable: false);
}

DateTime _bucketStart(DateTime date, SummaryBucket bucket) {
  final day = DateTime(date.year, date.month, date.day);
  if (bucket == SummaryBucket.daily) return day;
  // Weekly: rewind to Monday. DateTime.weekday is 1 (Mon) .. 7 (Sun).
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}
