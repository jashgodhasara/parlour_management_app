import '../../../../core/utils/result.dart';
import '../monthly_summary.dart';
import '../report_repository.dart';

class GetMonthlySummaryUseCase {
  final ReportRepository _repository;
  GetMonthlySummaryUseCase(this._repository);

  Future<Result<MonthlySummary>> call(int year, int month) async {
    return _repository.getMonthlySummary(year, month);
  }
}
