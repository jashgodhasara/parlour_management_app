import '../../../../core/utils/result.dart';
import '../domain/app_settings_entity.dart';
import '../domain/settings_repository.dart';
import 'settings_dao.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsDao _dao;

  SettingsRepositoryImpl(this._dao);

  @override
  Future<Result<AppSettingsEntity>> getSettings() async {
    try {
      final settings = await _dao.getSettings();
      return Success(settings);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> saveSettings(AppSettingsEntity settings) async {
    try {
      await _dao.saveSettings(settings);
      return const Success(null);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Stream<AppSettingsEntity> watchSettings() {
    return _dao.watchSettings();
  }
}
