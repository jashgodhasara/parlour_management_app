class MonthlySummary {
  final int year;
  final int month;
  final int visitCount;
  final double totalRevenue;
  final double totalDiscounts;
  final double totalOutstanding;
  final Map<String, double> revenueByCategory;

  const MonthlySummary({
    required this.year,
    required this.month,
    required this.visitCount,
    required this.totalRevenue,
    required this.totalDiscounts,
    required this.totalOutstanding,
    required this.revenueByCategory,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonthlySummary &&
          runtimeType == other.runtimeType &&
          year == other.year &&
          month == other.month &&
          visitCount == other.visitCount &&
          totalRevenue == other.totalRevenue &&
          totalDiscounts == other.totalDiscounts &&
          totalOutstanding == other.totalOutstanding;

  @override
  int get hashCode =>
      Object.hash(year, month, visitCount, totalRevenue, totalDiscounts, totalOutstanding);

  @override
  String toString() =>
      'MonthlySummary(year: $year, month: $month, visitCount: $visitCount, totalRevenue: $totalRevenue)';
}
