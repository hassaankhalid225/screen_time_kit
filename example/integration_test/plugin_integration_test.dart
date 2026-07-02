// Integration tests for screen_time_kit.
//
// Unlike the unit tests in `test/`, these run inside a full Flutter app on a
// real device or emulator and exercise the actual native implementation.
//
// ⚠️ REQUIRES A REAL DEVICE / EMULATOR:
//   * The permission and usage-stats flows below need a live platform.
//   * On iOS, Family Controls does NOT work reliably on the Simulator — run
//     these on a physical device signed with a team that has the Family
//     Controls capability.
//
// Run with:
//   flutter test integration_test/plugin_integration_test.dart
//
// For more information: https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:screen_time_kit/screen_time_kit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final plugin = ScreenTimeKit();

  testWidgets('getPlatformVersion returns a non-empty string', (
    WidgetTester tester,
  ) async {
    final version = await plugin.getPlatformVersion();
    expect(version, isNotNull);
    expect(version!.isNotEmpty, isTrue);
  });

  testWidgets('checkPermissionStatus returns a valid enum value', (
    WidgetTester tester,
  ) async {
    // Does not prompt — safe to run headless. On a fresh install this is
    // usually `denied` (Android) or `notDetermined` (iOS).
    final status = await plugin.checkPermissionStatus();
    expect(PermissionStatus.values, contains(status));
  });

  testWidgets('getActiveLimits round-trips a set limit (device only)', (
    WidgetTester tester,
  ) async {
    // Skipped automatically unless permission has been granted, because writing
    // limits requires authorization on both platforms.
    final status = await plugin.checkPermissionStatus();
    if (!status.isGranted) {
      // ignore: avoid_print
      print(
        'SKIP: permission not granted; grant Usage access / Family '
        'Controls and re-run to exercise the limits path.',
      );
      return;
    }

    await plugin.setAppLimit('com.example.app', const Duration(hours: 1));
    final limits = await plugin.getActiveLimits();
    expect(limits.any((l) => l.packageName == 'com.example.app'), isTrue);
    await plugin.clearAllLimits();
  });

  // Manual-only: requestPermission() shows platform UI and cannot be asserted
  // headlessly. Verify it by hand via the example app (see example/README.md).
}
