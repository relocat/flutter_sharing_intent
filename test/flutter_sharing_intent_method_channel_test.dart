// SPDX-License-Identifier: Apache-2.0
// Modified by Relocat (2026); see NOTICE.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent_method_channel.dart';

void main() {
  MethodChannelFlutterSharingIntent platform =
      MethodChannelFlutterSharingIntent();
  const MethodChannel channel = MethodChannel('flutter_sharing_intent');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  group('cleanup', () {
    test('passes the paths and returns the removed count', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        received = call;
        return 2;
      });
      expect(await platform.cleanup(['/a/b/c', '/a/b/d']), 2);
      expect(received?.method, 'cleanup');
      expect(received?.arguments, {
        'paths': ['/a/b/c', '/a/b/d'],
      });
    });

    test('treats a missing reply as zero removed files', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async => null);
      expect(await platform.cleanup(['/a/b/c']), 0);
    });
  });
}
