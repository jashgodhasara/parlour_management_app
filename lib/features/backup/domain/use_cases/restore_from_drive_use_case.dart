import '../../../../core/utils/result.dart';
import '../backup_repository.dart';

class RestoreFromDriveUseCase {
  final BackupRepository _repository;
  RestoreFromDriveUseCase(this._repository);

  Future<Result<void>> call() async {
    return _repository.restoreFromGoogleDrive();
  }
}
