import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:screen_time_kit/screen_time_kit.dart';

/// An in-memory fake platform so we can unit-test the Dart-side orchestration
/// (aggregation in 5.5, focus mode in 5.6) without a real device.
class MockScreenTimeKitPlatform
    with MockPlatformInterfaceMixin
    implements ScreenTimeKitPlatform {
  PermissionStatus statusToReturn = PermissionStatus.granted;
  List<AppUsageInfo> usageToReturn = const [];

  final Map<String, Duration> limits = {};
  final List<String> calls = [];

  @override
  Future<String?> getPlatformVersion() async => 'Mock 1.0';

  @override
  Future<PermissionStatus> checkPermissionStatus() async => statusToReturn;

  @override
  Future<PermissionStatus> requestPermission() async {
    calls.add('requestPermission');
    return statusToReturn;
  }

  @override
  Future<void> openSettings() async => calls.add('openSettings');

  @override
  Future<List<AppUsageInfo>> getAppUsage({
    required DateTime start,
    required DateTime end,
  }) async {
    calls.add('getAppUsage');
    return usageToReturn;
  }

  @override
  Future<void> setAppLimit(String packageName, Duration limit) async {
    limits[packageName] = limit;
  }

  @override
  Future<void> removeAppLimit(String packageName) async {
    limits.remove(packageName);
  }

  @override
  Future<List<AppLimit>> getActiveLimits() async => limits.entries
      .map((e) => AppLimit(packageName: e.key, limit: e.value))
      .toList();

  @override
  Future<void> clearAllLimits() async => limits.clear();

  @override
  Stream<AppLimitEvent> get onLimitReached => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockScreenTimeKitPlatform platform;
  late ScreenTimeKit screenTime;

  setUp(() {
    platform = MockScreenTimeKitPlatform();
    ScreenTimeKitPlatform.instance = platform;
    screenTime = ScreenTimeKit();
  });

  group('permissions', () {
    test('checkPermissionStatus passes through platform value', () async {
      platform.statusToReturn = PermissionStatus.denied;
      expect(await screenTime.checkPermissionStatus(), PermissionStatus.denied);
    });

    test('requestPermission delegates to platform', () async {
      await screenTime.requestPermission();
      expect(platform.calls, contains('requestPermission'));
    });

    test('PermissionStatus.fromName falls back to denied on garbage', () {
      expect(PermissionStatus.fromName('nonsense'), PermissionStatus.denied);
      expect(PermissionStatus.fromName(null), PermissionStatus.denied);
      expect(PermissionStatus.fromName('granted'), PermissionStatus.granted);
      expect(PermissionStatus.granted.isGranted, isTrue);
    });
  });

  group('app limits', () {
    test('set / get / remove / clear round-trips', () async {
      await screenTime.setAppLimit('com.a', const Duration(hours: 1));
      await screenTime.setAppLimit('com.b', const Duration(minutes: 30));

      var active = await screenTime.getActiveLimits();
      expect(active, hasLength(2));

      await screenTime.removeAppLimit('com.a');
      active = await screenTime.getActiveLimits();
      expect(active.single.packageName, 'com.b');

      await screenTime.clearAllLimits();
      expect(await screenTime.getActiveLimits(), isEmpty);
    });
  });

  group('focus mode (5.6)', () {
    test('applies zero-duration limits to every app', () async {
      await screenTime.startFocusMode(
        apps: const ['com.a', 'com.b'],
        duration: const Duration(minutes: 25),
      );
      expect(screenTime.isFocusModeActive, isTrue);
      expect(platform.limits.keys, containsAll(['com.a', 'com.b']));
      expect(platform.limits['com.a'], Duration.zero);
    });

    test('stopFocusMode reverts all applied limits', () async {
      await screenTime.startFocusMode(
        apps: const ['com.a', 'com.b'],
        duration: const Duration(minutes: 25),
      );
      await screenTime.stopFocusMode();
      expect(screenTime.isFocusModeActive, isFalse);
      expect(platform.limits, isEmpty);
    });

    test('timer auto-reverts a limit after the duration elapses', () {
      fakeAsync((async) {
        screenTime.startFocusMode(
          apps: const ['com.a'],
          duration: const Duration(minutes: 25),
        );
        async.flushMicrotasks();
        expect(platform.limits.containsKey('com.a'), isTrue);

        async.elapse(const Duration(minutes: 26));
        expect(platform.limits.containsKey('com.a'), isFalse);
        expect(screenTime.isFocusModeActive, isFalse);
      });
    });
  });

  group('summary aggregation (5.5)', () {
    final day1 = DateTime(2026, 1, 1, 9);
    final day1b = DateTime(2026, 1, 1, 20);
    final day2 = DateTime(2026, 1, 2, 12);

    test('daily buckets sum per-app usage within a day', () async {
      platform.usageToReturn = [
        AppUsageInfo(
          packageName: 'com.a',
          appName: 'A',
          usageDuration: const Duration(minutes: 10),
          date: day1,
        ),
        AppUsageInfo(
          packageName: 'com.a',
          appName: 'A',
          usageDuration: const Duration(minutes: 5),
          date: day1b,
        ),
        AppUsageInfo(
          packageName: 'com.b',
          appName: 'B',
          usageDuration: const Duration(minutes: 30),
          date: day2,
        ),
      ];

      final summaries =
          await screenTime.getDailySummaries(since: DateTime(2026, 1, 1));
      expect(summaries, hasLength(2));
      expect(summaries.first.perApp['com.a'], const Duration(minutes: 15));
      expect(summaries.first.total, const Duration(minutes: 15));
      expect(summaries.last.perApp['com.b'], const Duration(minutes: 30));
    });

    test('weekly bucket groups the same ISO week together', () async {
      platform.usageToReturn = [
        AppUsageInfo(
          packageName: 'com.a',
          appName: 'A',
          usageDuration: const Duration(minutes: 10),
          date: DateTime(2026, 1, 1), // Thu
        ),
        AppUsageInfo(
          packageName: 'com.a',
          appName: 'A',
          usageDuration: const Duration(minutes: 20),
          date: DateTime(2026, 1, 3), // Sat, same week
        ),
      ];
      final summaries =
          await screenTime.getWeeklySummaries(since: DateTime(2025, 12, 29));
      expect(summaries, hasLength(1));
      expect(summaries.single.perApp['com.a'], const Duration(minutes: 30));
      // Week starts Monday 2025-12-29.
      expect(summaries.single.start, DateTime(2025, 12, 29));
    });

    test('rankedApps sorts by descending usage', () {
      final summary = UsageSummary(
        start: day1,
        end: day2,
        perApp: const {
          'com.a': Duration(minutes: 5),
          'com.b': Duration(minutes: 50),
        },
      );
      expect(summary.rankedApps.first.key, 'com.b');
    });
  });

  group('model serialization', () {
    test('AppUsageInfo round-trips through a map', () {
      final info = AppUsageInfo(
        packageName: 'com.a',
        appName: 'A',
        usageDuration: const Duration(minutes: 12),
        date: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(AppUsageInfo.fromMap(info.toMap()), info);
    });

    test('AppUsageInfo.fromMap falls back appName to packageName', () {
      final info = AppUsageInfo.fromMap(const {
        'packageName': 'com.a',
        'appName': '',
        'usageMillis': 0,
        'dateMillis': 0,
      });
      expect(info.appName, 'com.a');
    });
  });
}
