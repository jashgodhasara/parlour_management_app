class DailySummary {
  final DateTime date;
  final int visitCount;
  final double totalRevenue;
  final double totalOutstanding;

  const DailySummary({
    required this.date,
    required this.visitCount,
    required this.totalRevenue,
    required this.totalOutstanding,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailySummary &&
          runtimeType == other.runtimeType &&
          date == other.date &&
          visitCount == other.visitCount &&
          totalRevenue == other.totalRevenue &&
          totalOutstanding == other.totalOutstanding;

  @override
  int get hashCode => Object.hash(date, visitCount, totalRevenue, totalOutstanding);

  @override
  String toString() =>
      'DailySummary(date: $date, visitCount: $visitCount, totalRevenue: $totalRevenue)';
}
