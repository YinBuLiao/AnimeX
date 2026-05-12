import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which bangumi titles the user has successfully subscribed to on
/// this device. The backend stores subscriptions globally (no per-user
/// list endpoint yet), so this is a best-effort local mirror — enough to
/// keep the 订阅 button reflecting reality between visits.
class SubscribedStore {
  static const _key = 'animex.subscribed.titles.v1';

  final SharedPreferences _prefs;
  SubscribedStore._(this._prefs);

  static Future<SubscribedStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SubscribedStore._(prefs);
  }

  Set<String> get all =>
      (_prefs.getStringList(_key) ?? const <String>[]).toSet();

  bool isSubscribed(String title) => all.contains(title.trim());

  Future<void> add(String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    final set = all..add(t);
    await _prefs.setStringList(_key, set.toList());
  }

  Future<void> remove(String title) async {
    final set = all..remove(title.trim());
    await _prefs.setStringList(_key, set.toList());
  }
}
