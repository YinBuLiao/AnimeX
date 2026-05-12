import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

enum LibrarySort {
  recentlyWatched,
  titleAscending,
  episodeCountDescending;

  String get label {
    switch (this) {
      case LibrarySort.recentlyWatched:
        return '最近观看';
      case LibrarySort.titleAscending:
        return '标题 A→Z';
      case LibrarySort.episodeCountDescending:
        return '集数多→少';
    }
  }
}

/// User-tweakable preferences persisted to SharedPreferences. Defaults are
/// chosen to match a typical mobile streaming experience.
class AppPreferences extends ChangeNotifier {
  static const _kAutoPlayNext = 'animex.pref.autoPlayNext';
  static const _kDefaultVolume = 'animex.pref.defaultVolume';
  static const _kPreferHighQuality = 'animex.pref.preferHighQuality';
  static const _kLibrarySort = 'animex.pref.librarySort';
  static const _kThemeMode = 'animex.pref.themeMode';
  static const _kEpisodeSortDescending = 'animex.pref.episodeSortDescending';

  final SharedPreferences _prefs;

  bool _autoPlayNext;
  double _defaultVolume;
  bool _preferHighQuality;
  LibrarySort _librarySort;
  ThemeMode _themeMode;
  bool _episodeSortDescending;

  AppPreferences._(this._prefs)
      : _autoPlayNext = _prefs.getBool(_kAutoPlayNext) ?? true,
        _defaultVolume = _prefs.getDouble(_kDefaultVolume) ?? 100.0,
        _preferHighQuality = _prefs.getBool(_kPreferHighQuality) ?? true,
        _librarySort = LibrarySort.values.firstWhere(
          (s) => s.name == _prefs.getString(_kLibrarySort),
          orElse: () => LibrarySort.recentlyWatched,
        ),
        _themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == _prefs.getString(_kThemeMode),
          orElse: () => ThemeMode.dark,
        ),
        _episodeSortDescending =
            _prefs.getBool(_kEpisodeSortDescending) ?? false;

  static Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences._(prefs);
  }

  bool get autoPlayNext => _autoPlayNext;
  double get defaultVolume => _defaultVolume;
  bool get preferHighQuality => _preferHighQuality;
  LibrarySort get librarySort => _librarySort;
  ThemeMode get themeMode => _themeMode;
  bool get episodeSortDescending => _episodeSortDescending;

  Future<void> setAutoPlayNext(bool v) async {
    _autoPlayNext = v;
    await _prefs.setBool(_kAutoPlayNext, v);
    notifyListeners();
  }

  Future<void> setDefaultVolume(double v) async {
    _defaultVolume = v.clamp(0.0, 100.0);
    await _prefs.setDouble(_kDefaultVolume, _defaultVolume);
    notifyListeners();
  }

  Future<void> setPreferHighQuality(bool v) async {
    _preferHighQuality = v;
    await _prefs.setBool(_kPreferHighQuality, v);
    notifyListeners();
  }

  Future<void> setLibrarySort(LibrarySort v) async {
    _librarySort = v;
    await _prefs.setString(_kLibrarySort, v.name);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode v) async {
    _themeMode = v;
    await _prefs.setString(_kThemeMode, v.name);
    notifyListeners();
  }

  Future<void> setEpisodeSortDescending(bool v) async {
    _episodeSortDescending = v;
    await _prefs.setBool(_kEpisodeSortDescending, v);
    notifyListeners();
  }
}
