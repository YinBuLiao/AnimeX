import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-tweakable preferences persisted to SharedPreferences. Defaults are
/// chosen to match a typical mobile streaming experience.
class AppPreferences extends ChangeNotifier {
  static const _kAutoPlayNext = 'animex.pref.autoPlayNext';
  static const _kDefaultVolume = 'animex.pref.defaultVolume';
  static const _kPreferHighQuality = 'animex.pref.preferHighQuality';

  final SharedPreferences _prefs;

  bool _autoPlayNext;
  double _defaultVolume;
  bool _preferHighQuality;

  AppPreferences._(this._prefs)
      : _autoPlayNext = _prefs.getBool(_kAutoPlayNext) ?? true,
        _defaultVolume = _prefs.getDouble(_kDefaultVolume) ?? 100.0,
        _preferHighQuality = _prefs.getBool(_kPreferHighQuality) ?? true;

  static Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences._(prefs);
  }

  bool get autoPlayNext => _autoPlayNext;
  double get defaultVolume => _defaultVolume;
  bool get preferHighQuality => _preferHighQuality;

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
}
