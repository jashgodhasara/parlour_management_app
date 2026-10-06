import 'dart:async';

import '../domain/app_settings_entity.dart';

/// In-memory DAO for app settings.
/// Replace with SharedPreferences or Drift once Flutter SDK is available.
class SettingsDao {
  AppSettingsEntity _current = AppSettingsEntity.defaults;
  final StreamController<AppSettingsEntity> _controller =
      StreamController<AppSettingsEntity>.broadcast();

  Future<AppSettingsEntity> getSettings() async {
    return _current;
  }

  Future<void> saveSettings(AppSettingsEntity settings) async {
    _current = settings;
    _controller.add(_current);
  }

  Stream<AppSettingsEntity> watchSettings() {
    return _controller.stream;
  }

  void dispose() {
    _controller.close();
  }
}
