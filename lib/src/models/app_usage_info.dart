import 'package:flutter/foundation.dart';

/// Aggregated foreground-usage for a single app over a time window.
///
/// One instance represents "app X was in the foreground for [usageDuration] on
/// [date]". The exact granularity of [date] depends on the platform query — for
/// a daily query it is the start of the day the sample belongs to.
@immutable
class AppUsageInfo {
  /// Creates an [AppUsageInfo].
  const AppUsageInfo({
    required this.packageName,
    required this.appName,
    required this.usageDuration,
    required this.date,
  });

  /// Platform identifier for the app.
  ///
  /// On Android this is the package name (e.g. `com.instagram.android`). On iOS
  /// raw bundle identifiers are not exposed for privacy reasons; this may be an
  /// opaque, app-scoped token instead. Do not assume it is globally stable
  /// across platforms.
  final String packageName;

  /// Human-readable app label (e.g. `Instagram`).
  ///
  /// Falls back to [packageName] when the platform cannot resolve a label
  /// (common on Android 11+ without `QUERY_ALL_PACKAGES`, and on iOS where the
  /// system provides a display token rather than a name).
  final String appName;

  /// Total foreground time within the queried window.
  final Duration usageDuration;

  /// The day / bucket this usage sample belongs to.
  final DateTime date;

  /// Builds an [AppUsageInfo] from a platform-channel map.
  factory AppUsageInfo.fromMap(Map<Object?, Object?> map) {
    final packageName = (map['packageName'] as String?) ?? '';
    return AppUsageInfo(
      packageName: packageName,
      appName: (map['appName'] as String?)?.isNotEmpty == true
          ? map['appName'] as String
          : packageName,
      usageDuration:
          Duration(milliseconds: (map['usageMillis'] as num?)?.toInt() ?? 0),
      date: DateTime.fromMillisecondsSinceEpoch(
          (map['dateMillis'] as num?)?.toInt() ?? 0),
    );
  }

  /// Serialises this value to a platform-channel-friendly map.
  Map<String, Object?> toMap() => <String, Object?>{
        'packageName': packageName,
        'appName': appName,
        'usageMillis': usageDuration.inMilliseconds,
        'dateMillis': date.millisecondsSinceEpoch,
      };

  /// Returns a copy with the given fields replaced.
  AppUsageInfo copyWith({
    String? packageName,
    String? appName,
    Duration? usageDuration,
    DateTime? date,
  }) {
    return AppUsageInfo(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      usageDuration: usageDuration ?? this.usageDuration,
      date: date ?? this.date,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppUsageInfo &&
      other.packageName == packageName &&
      other.appName == appName &&
      other.usageDuration == usageDuration &&
      other.date == date;

  @override
  int get hashCode => Object.hash(packageName, appName, usageDuration, date);

  @override
  String toString() =>
      'AppUsageInfo($appName [$packageName]: ${usageDuration.inMinutes}m on $date)';
}
