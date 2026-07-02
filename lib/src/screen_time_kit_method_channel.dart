import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'exceptions/screen_time_exceptions.dart';
import 'models/app_limit.dart';
import 'models/app_usage_info.dart';
import 'models/permission_status.dart';
import 'screen_time_kit_platform_interface.dart';

/// The default [ScreenTimeKitPlatform] implementation, backed by a
/// [MethodChannel] (+ [EventChannel] for limit events).
///
/// Every native call is wrapped so that a [PlatformException] is translated into
/// the typed hierarchy in `screen_time_exceptions.dart` — callers never see a
/// raw platform error.
class MethodChannelScreenTimeKit extends ScreenTimeKitPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('screen_time_kit');

  /// The event channel that streams [AppLimitEvent]s from the native side.
  @visibleForTesting
  final EventChannel limitEventsChannel =
      const EventChannel('screen_time_kit/limit_events');

  Stream<AppLimitEvent>? _onLimitReached;

  /// Runs [action], converting any [PlatformException] into a
  /// [ScreenTimeException].
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      throw ScreenTimeException.fromPlatform(e);
    } on MissingPluginException catch (e) {
      throw PlatformNotSupportedException(
        e.message ?? 'screen_time_kit is not available on this platform.',
      );
    }
  }

  @override
  Future<String?> getPlatformVersion() {
    return _guard(
        () => methodChannel.invokeMethod<String>('getPlatformVersion'));
  }

  @override
  Future<PermissionStatus> checkPermissionStatus() {
    return _guard(() async {
      final name =
          await methodChannel.invokeMethod<String>('checkPermissionStatus');
      return PermissionStatus.fromName(name);
    });
  }

  @override
  Future<PermissionStatus> requestPermission() {
    return _guard(() async {
      final name =
          await methodChannel.invokeMethod<String>('requestPermission');
      return PermissionStatus.fromName(name);
    });
  }

  @override
  Future<void> openSettings() {
    return _guard(() => methodChannel.invokeMethod<void>('openSettings'));
  }

  @override
  Future<List<AppUsageInfo>> getAppUsage({
    required DateTime start,
    required DateTime end,
  }) {
    return _guard(() async {
      final raw = await methodChannel.invokeListMethod<Map<Object?, Object?>>(
        'getAppUsage',
        <String, Object?>{
          'startMillis': start.millisecondsSinceEpoch,
          'endMillis': end.millisecondsSinceEpoch,
        },
      );
      if (raw == null) return const <AppUsageInfo>[];
      return raw.map(AppUsageInfo.fromMap).toList(growable: false);
    });
  }

  @override
  Future<void> setAppLimit(String packageName, Duration limit) {
    return _guard(
        () => methodChannel.invokeMethod<void>('setAppLimit', <String, Object?>{
              'packageName': packageName,
              'limitMillis': limit.inMilliseconds,
            }));
  }

  @override
  Future<void> removeAppLimit(String packageName) {
    return _guard(() =>
        methodChannel.invokeMethod<void>('removeAppLimit', <String, Object?>{
          'packageName': packageName,
        }));
  }

  @override
  Future<List<AppLimit>> getActiveLimits() {
    return _guard(() async {
      final raw = await methodChannel
          .invokeListMethod<Map<Object?, Object?>>('getActiveLimits');
      if (raw == null) return const <AppLimit>[];
      return raw.map(AppLimit.fromMap).toList(growable: false);
    });
  }

  @override
  Future<void> clearAllLimits() {
    return _guard(() => methodChannel.invokeMethod<void>('clearAllLimits'));
  }

  @override
  Stream<AppLimitEvent> get onLimitReached {
    return _onLimitReached ??= limitEventsChannel.receiveBroadcastStream().map(
        (event) =>
            AppLimitEvent.fromMap((event as Map).cast<Object?, Object?>()));
  }
}
