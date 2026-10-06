import '../../../core/utils/result.dart';
import 'backup_data.dart';

abstract class BackupRepository {
  Future<Result<void>> backupToGoogleDrive();
  Future<Result<void>> restoreFromGoogleDrive();
  Future<Result<void>> restoreFromJson(String jsonString);
  Future<Result<String>> exportAsJson();
  Future<Result<String>> exportAsCsv();
  Future<Result<BackupConflict?>> detectConflict();
  Future<Result<void>> resolveConflict(ConflictResolution resolution);
}
