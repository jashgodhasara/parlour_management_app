import '../../../core/utils/result.dart';
import 'payment.dart';

abstract class PaymentRepository {
  Future<Result<Payment>> recordPayment({
    required String billId,
    required double amount,
    required PaymentMethod method,
  });
  Future<Result<List<Payment>>> getPaymentsForBill(String billId);
  Future<Result<double>> getOutstandingBalance(String billId);
}
