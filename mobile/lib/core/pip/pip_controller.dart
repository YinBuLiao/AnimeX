import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Picture-in-Picture bridge for Android. iOS PiP is provided by the
/// system AVPictureInPictureController via media_kit — no Dart bridge
/// needed there.
class PipController {
  static const _channel = MethodChannel('animex/pip');

  /// Tell the platform to auto-enter PiP on the next onUserLeaveHint
  /// (home button / app switcher). aspect = video width / height ratio.
  /// Returns true if PiP is supported and the request was accepted.
  static Future<bool> setEnabled({
    required bool enabled,
    int aspectNumerator = 16,
    int aspectDenominator = 9,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setEnabled', {
        'enabled': enabled,
        'aspectNumerator': aspectNumerator,
        'aspectDenominator': aspectDenominator,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Enter PiP immediately (used by an in-player button).
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
