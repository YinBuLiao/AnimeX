import 'dart:io' show Platform;

import 'package:animex_mobile/data/repositories/notifications_repository.dart';

/// Fetches a push token from the underlying platform. The default
/// implementation is a no-op so the rest of the app compiles and runs
/// without a Firebase project. Replace with a firebase_messaging-backed
/// implementation in main.dart once the operator provisions
/// google-services.json + GoogleService-Info.plist.
abstract class PushTokenSource {
  Future<String?> obtainToken();
}

class NoopPushTokenSource implements PushTokenSource {
  const NoopPushTokenSource();
  @override
  Future<String?> obtainToken() async => null;
}

/// Best-effort: ask the platform for an FCM token and POST it to the
/// backend. Failures are swallowed because notification center pull-based
/// refresh still works without push registration.
Future<void> registerDeviceForPush({
  required PushTokenSource source,
  required NotificationsRepository repo,
}) async {
  String? token;
  try {
    token = await source.obtainToken();
  } catch (_) {
    return;
  }
  if (token == null || token.isEmpty) return;
  final platform = Platform.isIOS ? 'ios' : 'android';
  try {
    await repo.registerDevice(fcmToken: token, platform: platform);
  } catch (_) {
    // Swallow: pull-based refresh is the supported fallback.
  }
}
