import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Persists remembered watches and settings on the phone.
class Storage {
  static const _kDevices = 'saved_devices_v1';
  static const _kSettings = 'settings_v1';

  Future<List<SavedDevice>> loadDevices() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kDevices);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SavedDevice.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDevices(List<SavedDevice> devices) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kDevices, jsonEncode(devices.map((d) => d.toJson()).toList()));
  }

  Future<AppSettings> loadSettings() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSettings);
    if (raw == null) return AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSettings, jsonEncode(s.toJson()));
  }
}
