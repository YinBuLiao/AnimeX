import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Picture-in-Picture bridge for Android. iOS PiP is provided by the
/// system AVPictureInPictureController via media_kit — no Dart bridge
/// needed there.
class PipController {
  static const _channel = MethodChannel('animex/pip');

  /// Enter PiP immediately. Called by the player page's in-app PiP button
  /// and from a WidgetsBindingObserver when the app moves to the inactive
  /// state — so only the player page can trigger PiP, never other tabs.
  static Future<bool> enterNow() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('enterNow');
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('supported');
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
