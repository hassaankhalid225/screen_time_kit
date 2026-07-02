import 'package:flutter/foundation.dart';

import 'app_usage_info.dart';

/// A rolled-up usage report for a single bucket of time (a day or a week).
///
/// Produced entirely in Dart by aggregating [AppUsageInfo] samples — see
/// `ScreenTimeKit.getDailySummaries` / `getWeeklySummaries`. No native code is
/// involved, so this works identically on every platform.
@immutable
class UsageSummary {
  /// Creates a [UsageSummary].
  const UsageSummary({
    required this.start,
    required this.end,
    required this.perApp,
  });

  /// Inclusive start of the bucket.
  final DateTime start;

  /// Exclusive end of the bucket.
  final DateTime end;

  /// Total foreground time per app within the bucket, keyed by package name.
  final Map<String, Duration> perApp;

  /// Total device foreground time across all apps in the bucket.
  Duration get total => perApp.values.fold(Duration.zero, (sum, d) => sum + d);

  /// Apps sorted by descending usage. Handy for "top apps" lists.
  List<MapEntry<String, Duration>> get rankedApps {
    final entries = perApp.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  @override
  String toString() =>
      'UsageSummary($start..$end, total=${total.inMinutes}m, apps=${perApp.length})';
}
