import '../../../../core/utils/result.dart';
import '../daily_summary.dart';
import '../report_repository.dart';

class GetDailySummaryUseCase {
  final ReportRepository _repository;
  GetDailySummaryUseCase(this._repository);

  Future<Result<DailySummary>> call(DateTime date) async {
    return _repository.getDailySummary(date);
  }
}
