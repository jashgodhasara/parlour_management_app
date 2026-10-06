import '../../../core/utils/result.dart';
import 'app_settings_entity.dart';

abstract class SettingsRepository {
  Future<Result<AppSettingsEntity>> getSettings();
  Future<Result<void>> saveSettings(AppSettingsEntity settings);
  Stream<AppSettingsEntity> watchSettings();
}
