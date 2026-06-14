import 'package:shared_preferences/shared_preferences.dart';

class UpdatePreferences {
  static const _kAutoUpdate = 'auto_update_enabled';
  static const _kLastCheck = 'update_last_check_ms';

  Future<bool> autoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoUpdate) ?? true;
  }

  Future<void> setAutoUpdateEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoUpdate, value);
  }

  Future<void> markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastCheck, DateTime.now().millisecondsSinceEpoch);
  }
}
