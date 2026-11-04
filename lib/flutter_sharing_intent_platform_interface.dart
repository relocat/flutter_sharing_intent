// SPDX-License-Identifier: Apache-2.0
// Modified by Relocat (2026); see NOTICE.
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_sharing_intent_method_channel.dart';

abstract class FlutterSharingIntentPlatform extends PlatformInterface {
  /// Constructs a FlutterSharingIntentPlatform.
  FlutterSharingIntentPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterSharingIntentPlatform _instance =
      MethodChannelFlutterSharingIntent();

  /// The default instance of [FlutterSharingIntentPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterSharingIntent].
  static FlutterSharingIntentPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterSharingIntentPlatform] when
  /// they register themselves.
  static set instance(FlutterSharingIntentPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<List<SharedFile>> getInitialSharing() async {
    throw UnimplementedError('getInitialSharing() has not been implemented.');
  }

  void reset() async {
    throw UnimplementedError('reset() has not been implemented.');
  }

  /// Deletes the listed App Group container file paths. Use after your app
  /// has finished reading the shared files to minimize on-disk plaintext
  /// exposure (FSI-31). On iOS only files the share extension wrote into the
  /// plugin directories of the App Group container are deleted; on Android
  /// only the plugin's own copies and thumbnails in the cache directory are.
  /// Every other path is ignored.
  ///
  /// Returns how many files were deleted.
  Future<int> cleanup(List<String> paths) {
    throw UnimplementedError('cleanup() has not been implemented.');
  }
}
