import '../../../../core/utils/result.dart';
import '../app_settings_entity.dart';
import '../settings_repository.dart';

class SaveSettingsUseCase {
  final SettingsRepository _repository;
  SaveSettingsUseCase(this._repository);

  Future<Result<void>> call(AppSettingsEntity settings) async {
    return _repository.saveSettings(settings);
  }
}
