import '../../../core/utils/result.dart';
import '../../billing/domain/bill.dart';
import '../../billing/domain/billing_repository.dart';
import '../../customers/data/customers_dao.dart';
import '../../payments/domain/payment.dart';
import '../../payments/domain/payment_repository.dart';
import '../domain/customer_balance.dart';
import '../domain/daily_summary.dart';
import '../domain/monthly_summary.dart';
import '../domain/report_repository.dart';
import '../domain/statement_transaction.dart';

class ReportRepositoryImpl implements ReportRepository {
  final BillingRepository _billingRepository;
  final PaymentRepository _paymentRepository;
  final CustomersDao _customersDao;

  ReportRepositoryImpl(
    this._billingRepository,
    this._paymentRepository,
    this._customersDao,
  );

  @override
  Future<Result<DailySummary>> getDailySummary(DateTime date) async {
    try {
      // We need all bills — BillingRepository doesn't expose getAllBills,
      // so we iterate all customers and collect their bills.
      final allBills = await _getAllBills();

      final dayBills = allBills.where((b) {
        final d = b.visitDate;
        return d.year == date.year &&
            d.month == date.month &&
            d.day == date.day;
      }).toList();

      double totalRevenue = 0;
      double totalOutstanding = 0;

      for (final bill in dayBills) {
        totalRevenue += bill.total;
        final balanceResult =
            await _paymentRepository.getOutstandingBalance(bill.id);
        if (balanceResult is Success<double>) {
          totalOutstanding += balanceResult.value;
        }
      }

      return Success(DailySummary(
        date: DateTime(date.year, date.month, date.day),
        visitCount: dayBills.length,
        totalRevenue: totalRevenue,
        totalOutstanding: totalOutstanding,
      ));
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<MonthlySummary>> getMonthlySummary(int year, int month) async {
    try {
      final allBills = await _getAllBills();

      final monthBills = allBills.where((b) {
        return b.visitDate.year == year && b.visitDate.month == month;
      }).toList();

      double totalRevenue = 0;
      double totalDiscounts = 0;
      double totalOutstanding = 0;
      final revenueByCategory = <String, double>{};

      for (final bill in monthBills) {
        totalRevenue += bill.total;
        totalDiscounts += bill.discountAmount;

        final balanceResult =
            await _paymentRepository.getOutstandingBalance(bill.id);
        if (balanceResult is Success<double>) {
          totalOutstanding += balanceResult.value;
        }

        // Aggregate revenue by category using line items.
        // Line items don't carry categoryId directly, so we group by service name
        // as a best-effort. A full implementation would join with services table.
        for (final item in bill.lineItems) {
          revenueByCategory.update(
            item.serviceName,
            (existing) => existing + item.servicePrice,
            ifAbsent: () => item.servicePrice,
          );
        }
      }

      return Success(MonthlySummary(
        year: year,
        month: month,
        visitCount: monthBills.length,
        totalRevenue: totalRevenue,
        totalDiscounts: totalDiscounts,
        totalOutstanding: totalOutstanding,
        revenueByCategory: revenueByCategory,
      ));
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<CustomerBalance>>> getCustomersWithBalance() async {
    try {
      final customers = await _customersDao.getAllCustomers();
      final balances = <CustomerBalance>[];

      for (final customer in customers) {
        final billsResult =
            await _billingRepository.getBillsForCustomer(customer.id);
        if (billsResult is Failure) continue;

        final bills = (billsResult as Success<List<Bill>>).value;
        double outstanding = 0;
        for (final bill in bills) {
          final balanceResult =
              await _paymentRepository.getOutstandingBalance(bill.id);
          if (balanceResult is Success<double>) {
            outstanding += balanceResult.value;
          }
        }

        if (outstanding > 0) {
          balances.add(CustomerBalance(
            customerId: customer.id,
            customerName: customer.fullName,
            customerPhone: customer.phoneNumber,
            outstandingBalance: outstanding,
          ));
        }
      }

      balances
          .sort((a, b) => b.outstandingBalance.compareTo(a.outstandingBalance));
      return Success(balances);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<StatementTransaction>>> getTransactionsBetween(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final customers = await _customersDao.getAllCustomers();
      final transactions = <StatementTransaction>[];

      for (final customer in customers) {
        final billsResult =
            await _billingRepository.getBillsForCustomer(customer.id);
        if (billsResult is! Success<List<Bill>>) continue;

        final bills = billsResult.value.where((bill) {
          final date = bill.visitDate;
          return !date.isBefore(start) && date.isBefore(end);
        });

        for (final bill in bills) {
          final paymentsResult =
              await _paymentRepository.getPaymentsForBill(bill.id);
          final payments = paymentsResult is Success<List<Payment>>
              ? paymentsResult.value
              : const <Payment>[];
          final paidAmount = payments.fold<double>(
            0,
            (total, payment) => total + payment.amount,
          );
          final methods =
              payments.map((payment) => payment.method.name).toSet().join(', ');

          transactions.add(
            StatementTransaction(
              date: bill.visitDate,
              billId: bill.id,
              customerName: customer.fullName,
              customerPhone: customer.phoneNumber,
              services:
                  bill.lineItems.map((item) => item.serviceName).join(', '),
              billAmount: bill.total,
              paidAmount: paidAmount,
              outstandingAmount:
                  (bill.total - paidAmount).clamp(0.0, double.infinity),
              paymentMethods: methods.isEmpty ? '-' : methods,
            ),
          );
        }
      }

      transactions.sort((a, b) => a.date.compareTo(b.date));
      return Success(transactions);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  /// Helper: collect all bills across all customers.
  Future<List<Bill>> _getAllBills() async {
    final customers = await _customersDao.getAllCustomers();
    final allBills = <Bill>[];
    for (final customer in customers) {
      final result = await _billingRepository.getBillsForCustomer(customer.id);
      if (result is Success<List<Bill>>) {
        allBills.addAll(result.value);
      }
    }
    return allBills;
  }
}
