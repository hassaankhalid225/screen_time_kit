import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_time_kit/screen_time_kit.dart';
import 'package:screen_time_kit/src/screen_time_kit_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelScreenTimeKit();
  const channel = MethodChannel('screen_time_kit');
  final log = <MethodCall>[];

  void handleWith(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return handler(call);
    });
  }

  tearDown(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('checkPermissionStatus decodes the native enum name', () async {
    handleWith((_) => 'granted');
    expect(await platform.checkPermissionStatus(), PermissionStatus.granted);
    expect(log.single.method, 'checkPermissionStatus');
  });

  test('getAppUsage sends the time window and decodes the list', () async {
    handleWith((call) {
      expect(call.arguments['startMillis'], isA<int>());
      expect(call.arguments['endMillis'], isA<int>());
      return [
        {
          'packageName': 'com.a',
          'appName': 'App A',
          'usageMillis': 60000,
          'dateMillis': 1000,
        }
      ];
    });

    final usage = await platform.getAppUsage(
      start: DateTime.fromMillisecondsSinceEpoch(0),
      end: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(usage, hasLength(1));
    expect(usage.single.appName, 'App A');
    expect(usage.single.usageDuration, const Duration(minutes: 1));
  });

  test('setAppLimit forwards package + millis', () async {
    handleWith((_) => null);
    await platform.setAppLimit('com.a', const Duration(hours: 1));
    expect(log.single.method, 'setAppLimit');
    expect(log.single.arguments['packageName'], 'com.a');
    expect(log.single.arguments['limitMillis'],
        const Duration(hours: 1).inMilliseconds);
  });

  test('PERMISSION_DENIED maps to PermissionDeniedException', () async {
    handleWith((_) =>
        throw PlatformException(code: 'PERMISSION_DENIED', message: 'nope'));
    expect(
      () => platform.getAppUsage(
        start: DateTime.fromMillisecondsSinceEpoch(0),
        end: DateTime.fromMillisecondsSinceEpoch(1),
      ),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('ENTITLEMENT_MISSING maps to EntitlementMissingException', () async {
    handleWith((_) => throw PlatformException(code: 'ENTITLEMENT_MISSING'));
    expect(
      () => platform.requestPermission(),
      throwsA(isA<EntitlementMissingException>()),
    );
  });

  test('a missing plugin surfaces PlatformNotSupportedException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(
      () => platform.getActiveLimits(),
      throwsA(isA<PlatformNotSupportedException>()),
    );
  });
}
