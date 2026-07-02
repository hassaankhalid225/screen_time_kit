import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models/app_limit.dart';
import 'models/app_usage_info.dart';
import 'models/permission_status.dart';
import 'screen_time_kit_method_channel.dart';

/// The interface that platform implementations of `screen_time_kit` implement.
///
/// Platform implementations should extend this class rather than implement it
/// as `screen_time_kit` does not consider newly added methods to be breaking
/// changes. Extending this class (using `extends`) ensures that the subclass
/// will get the default implementation, while platform implementations that
/// `implements` this interface will be broken by newly added
/// [ScreenTimeKitPlatform] methods.
abstract class ScreenTimeKitPlatform extends PlatformInterface {
  /// Constructs a [ScreenTimeKitPlatform].
  ScreenTimeKitPlatform() : super(token: _token);

  static final Object _token = Object();

  static ScreenTimeKitPlatform _instance = MethodChannelScreenTimeKit();

  /// The default instance of [ScreenTimeKitPlatform] to use.
  ///
  /// Defaults to [MethodChannelScreenTimeKit].
  static ScreenTimeKitPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ScreenTimeKitPlatform] when they
  /// register themselves.
  static set instance(ScreenTimeKitPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Diagnostic: returns the underlying OS version string.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Returns the current authorization state without prompting the user.
  Future<PermissionStatus> checkPermissionStatus() {
    throw UnimplementedError(
        'checkPermissionStatus() has not been implemented.');
  }

  /// Requests authorization.
  ///
  /// On iOS this shows Apple's Family Controls consent sheet. On Android there
  /// is no runtime dialog, so this opens the system Usage-access settings screen
  /// (via [openSettings]) and then reports the resulting status.
  Future<PermissionStatus> requestPermission() {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }

  /// Opens the platform settings screen relevant to this plugin.
  ///
  /// Android: `Settings.ACTION_USAGE_ACCESS_SETTINGS`. iOS: the app's settings
  /// page (authorization itself is handled by [requestPermission]).
  Future<void> openSettings() {
    throw UnimplementedError('openSettings() has not been implemented.');
  }

  /// Returns aggregated app usage between [start] and [end].
  Future<List<AppUsageInfo>> getAppUsage({
    required DateTime start,
    required DateTime end,
  }) {
    throw UnimplementedError('getAppUsage() has not been implemented.');
  }

  /// Configures a daily [limit] for [packageName].
  Future<void> setAppLimit(String packageName, Duration limit) {
    throw UnimplementedError('setAppLimit() has not been implemented.');
  }

  /// Removes any limit configured for [packageName].
  Future<void> removeAppLimit(String packageName) {
    throw UnimplementedError('removeAppLimit() has not been implemented.');
  }

  /// Returns all currently configured limits.
  Future<List<AppLimit>> getActiveLimits() {
    throw UnimplementedError('getActiveLimits() has not been implemented.');
  }

  /// Removes every configured limit.
  Future<void> clearAllLimits() {
    throw UnimplementedError('clearAllLimits() has not been implemented.');
  }

  /// A broadcast stream that fires whenever an app crosses its configured limit.
  ///
  /// On Android these events come from soft-limit tracking; on iOS the system
  /// enforces the limit and reports the crossing.
  Stream<AppLimitEvent> get onLimitReached {
    throw UnimplementedError('onLimitReached has not been implemented.');
  }
}
