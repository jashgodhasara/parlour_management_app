import '../../../../core/utils/result.dart';
import '../backup_repository.dart';

class ExportDataUseCase {
  final BackupRepository _repository;
  ExportDataUseCase(this._repository);

  Future<Result<String>> call({bool asCsv = false}) async {
    if (asCsv) {
      return _repository.exportAsCsv();
    }
    return _repository.exportAsJson();
  }
}
