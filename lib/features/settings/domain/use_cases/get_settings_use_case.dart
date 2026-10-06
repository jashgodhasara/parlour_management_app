import '../../../../core/utils/result.dart';
import '../app_settings_entity.dart';
import '../settings_repository.dart';

class GetSettingsUseCase {
  final SettingsRepository _repository;
  GetSettingsUseCase(this._repository);

  Future<Result<AppSettingsEntity>> call() async {
    return _repository.getSettings();
  }
  
}
