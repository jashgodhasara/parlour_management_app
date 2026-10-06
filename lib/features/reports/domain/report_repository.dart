import '../../../core/utils/result.dart';
import 'daily_summary.dart';
import 'monthly_summary.dart';
import 'customer_balance.dart';
import 'statement_transaction.dart';

abstract class ReportRepository {
  Future<Result<DailySummary>> getDailySummary(DateTime date);
  Future<Result<MonthlySummary>> getMonthlySummary(int year, int month);
  Future<Result<List<CustomerBalance>>> getCustomersWithBalance();
  Future<Result<List<StatementTransaction>>> getTransactionsBetween(
    DateTime start,
    DateTime end,
  );
}
