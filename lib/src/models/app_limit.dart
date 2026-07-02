import 'package:flutter/foundation.dart';

/// A daily usage limit configured for a single app.
///
/// **Platform behaviour differs — read carefully:**
/// * **iOS** enforces limits natively. Once Family Controls authorization is
///   granted, `ManagedSettings` can actually shield/block the app.
/// * **Android** has no OS-level API to block third-party apps. A limit here is
///   a *soft* limit: the plugin tracks usage and emits an [AppLimitEvent] via
///   `ScreenTimeKit.onLimitReached` when the threshold is crossed. It is up to
///   the host app to react (overlay, notification, etc.). The plugin cannot
///   force-close another app on Android.
@immutable
class AppLimit {
  /// Creates an [AppLimit].
  const AppLimit({required this.packageName, required this.limit});

  /// The app the limit applies to (Android package name / iOS token).
  final String packageName;

  /// Maximum allowed foreground time per day.
  final Duration limit;

  /// Builds an [AppLimit] from a platform-channel map.
  factory AppLimit.fromMap(Map<Object?, Object?> map) => AppLimit(
        packageName: (map['packageName'] as String?) ?? '',
        limit:
            Duration(milliseconds: (map['limitMillis'] as num?)?.toInt() ?? 0),
      );

  /// Serialises this value to a platform-channel-friendly map.
  Map<String, Object?> toMap() => <String, Object?>{
        'packageName': packageName,
        'limitMillis': limit.inMilliseconds,
      };

  @override
  bool operator ==(Object other) =>
      other is AppLimit &&
      other.packageName == packageName &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(packageName, limit);

  @override
  String toString() => 'AppLimit($packageName -> ${limit.inMinutes}m)';
}

/// Emitted on `ScreenTimeKit.onLimitReached` when an app crosses its limit.
@immutable
class AppLimitEvent {
  /// Creates an [AppLimitEvent].
  const AppLimitEvent({
    required this.packageName,
    required this.limit,
    required this.reachedAt,
  });

  /// The app whose limit was reached.
  final String packageName;

  /// The configured limit that was crossed.
  final Duration limit;

  /// When the crossing was detected.
  final DateTime reachedAt;

  /// Builds an [AppLimitEvent] from a platform-channel map.
  factory AppLimitEvent.fromMap(Map<Object?, Object?> map) => AppLimitEvent(
        packageName: (map['packageName'] as String?) ?? '',
        limit:
            Duration(milliseconds: (map['limitMillis'] as num?)?.toInt() ?? 0),
        reachedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['reachedAtMillis'] as num?)?.toInt() ?? 0,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is AppLimitEvent &&
      other.packageName == packageName &&
      other.limit == limit &&
      other.reachedAt == reachedAt;

  @override
  int get hashCode => Object.hash(packageName, limit, reachedAt);

  @override
  String toString() =>
      'AppLimitEvent($packageName reached ${limit.inMinutes}m at $reachedAt)';
}
