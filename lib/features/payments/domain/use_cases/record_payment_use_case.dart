import '../../../../core/utils/result.dart';
import '../../../billing/domain/billing_repository.dart';
import '../payment.dart';
import '../payment_repository.dart';

class RecordPaymentUseCase {
  final PaymentRepository _paymentRepository;
  final BillingRepository _billingRepository;
  RecordPaymentUseCase(this._paymentRepository, this._billingRepository);

  Future<Result<Payment>> call({
    required String billId,
    required double amount,
    required PaymentMethod method,
  }) async {
    // Check outstanding balance before recording.
    final balanceResult = await _paymentRepository.getOutstandingBalance(billId);
    if (balanceResult is Failure) {
      return Failure((balanceResult as Failure).failure);
    }
    final outstanding = (balanceResult as Success<double>).value;

    if (amount > outstanding) {
      return Failure(OverpaymentFailure(outstanding));
    }

    final paymentResult = await _paymentRepository.recordPayment(
      billId: billId,
      amount: amount,
      method: method,
    );
    if (paymentResult is Failure) return paymentResult;

    // If balance is now zero, mark the bill as paid.
    final newBalance = outstanding - amount;
    if (newBalance <= 0) {
      // Mark bill as paid via the billing repository.
      // BillingRepository.finaliseBill sets status to finalised;
      // for a fully-paid bill we update to paid status directly.
      await _billingRepository.markAsPaid(billId);
    }

    return paymentResult;
  }
}
