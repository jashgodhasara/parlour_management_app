import 'monthly_summary.dart';

class YearlySummary {
  final int year;
  final int visitCount;
  final double totalRevenue;
  final double totalDiscounts;
  final double totalOutstanding;
  final Map<String, double> revenueByCategory;
  final List<MonthlySummary> monthlySummaries;

  const YearlySummary({
    required this.year,
    required this.visitCount,
    required this.totalRevenue,
    required this.totalDiscounts,
    required this.totalOutstanding,
    required this.revenueByCategory,
    required this.monthlySummaries,
  });
}
