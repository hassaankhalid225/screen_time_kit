/// One Dart API for screen time, app usage, and app limits — Android and iOS,
/// unified.
///
/// Import this file to access the entire public surface:
///
/// ```dart
/// import 'package:screen_time_kit/screen_time_kit.dart';
///
/// final screenTime = ScreenTimeKit();
/// ```
library screen_time_kit;

export 'src/exceptions/screen_time_exceptions.dart';
export 'src/models/app_limit.dart';
export 'src/models/app_usage_info.dart';
export 'src/models/permission_status.dart';
export 'src/models/usage_summary.dart';
export 'src/screen_time_kit.dart';

// Exposed for platform implementations and tests that need to swap the backing
// platform instance (e.g. a MockScreenTimeKitPlatform).
export 'src/screen_time_kit_platform_interface.dart' show ScreenTimeKitPlatform;
