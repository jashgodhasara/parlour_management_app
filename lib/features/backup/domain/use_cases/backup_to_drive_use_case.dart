import '../../../../core/utils/result.dart';
import '../backup_repository.dart';

class BackupToDriveUseCase {
  final BackupRepository _repository;
  BackupToDriveUseCase(this._repository);

  Future<Result<void>> call() async {
    return _repository.backupToGoogleDrive();
  }
}
