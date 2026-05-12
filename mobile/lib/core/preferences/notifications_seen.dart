import 'package:shared_preferences/shared_preferences.dart';

/// Persists the unix timestamp of the most recent notification the user has
/// acknowledged (by opening the notifications page). The profile tab uses
/// it to compute the unread badge count.
class NotificationsSeenStore {
  static const _key = 'animex.notifications.lastSeen.v1';

  final SharedPreferences _prefs;
  NotificationsSeenStore._(this._prefs);

  static Future<NotificationsSeenStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationsSeenStore._(prefs);
  }

  int get lastSeenAt => _prefs.getInt(_key) ?? 0;

  Future<void> markSeen(int unixSec) async {
    if (unixSec <= lastSeenAt) return;
    await _prefs.setInt(_key, unixSec);
  }
}
