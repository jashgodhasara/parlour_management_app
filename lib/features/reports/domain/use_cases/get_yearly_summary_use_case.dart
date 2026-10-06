import '../../../../core/utils/result.dart';
import '../monthly_summary.dart';
import '../report_repository.dart';
import '../yearly_summary.dart';

class GetYearlySummaryUseCase {
  final ReportRepository _repository;

  GetYearlySummaryUseCase(this._repository);

  Future<Result<YearlySummary>> call(int year) async {
    try {
      final monthlySummaries = <MonthlySummary>[];
      final revenueByCategory = <String, double>{};
      var visitCount = 0;
      var totalRevenue = 0.0;
      var totalDiscounts = 0.0;
      var totalOutstanding = 0.0;

      for (var month = 1; month <= 12; month++) {
        final result = await _repository.getMonthlySummary(year, month);
        if (result is Failure<MonthlySummary>) {
          return Failure(result.failure);
        }

        final summary = (result as Success<MonthlySummary>).value;
        monthlySummaries.add(summary);
        visitCount += summary.visitCount;
        totalRevenue += summary.totalRevenue;
        totalDiscounts += summary.totalDiscounts;
        totalOutstanding += summary.totalOutstanding;

        for (final entry in summary.revenueByCategory.entries) {
          revenueByCategory.update(
            entry.key,
            (existing) => existing + entry.value,
            ifAbsent: () => entry.value,
          );
        }
      }

      return Success(
        YearlySummary(
          year: year,
          visitCount: visitCount,
          totalRevenue: totalRevenue,
          totalDiscounts: totalDiscounts,
          totalOutstanding: totalOutstanding,
          revenueByCategory: revenueByCategory,
          monthlySummaries: monthlySummaries,
        ),
      );
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }
}
