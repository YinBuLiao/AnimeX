import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's last N search queries in SharedPreferences so the
/// search page can offer them as quick-tap chips when the input is empty.
class SearchHistoryStore {
  static const _key = 'animex.search.history.v1';
  static const int maxEntries = 10;

  final SharedPreferences _prefs;
  SearchHistoryStore._(this._prefs);

  static Future<SearchHistoryStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SearchHistoryStore._(prefs);
  }

  List<String> get all => _prefs.getStringList(_key) ?? const <String>[];

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final list = all.toList();
    list.removeWhere((e) => e == q);
    list.insert(0, q);
    if (list.length > maxEntries) {
      list.removeRange(maxEntries, list.length);
    }
    await _prefs.setStringList(_key, list);
  }

  Future<void> remove(String query) async {
    final list = all.toList();
    list.removeWhere((e) => e == query);
    await _prefs.setStringList(_key, list);
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}
