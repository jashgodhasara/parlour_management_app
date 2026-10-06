import 'package:uuid/uuid.dart';

import '../../../../core/utils/result.dart';
import '../../../billing/domain/billing_repository.dart';
import '../domain/payment.dart';
import '../domain/payment_repository.dart';
import 'payments_dao.dart';

class PaymentRepositoryImpl implements PaymentRepository {
  final PaymentsDao _paymentsDao;
  final BillingRepository _billingRepository;
  final _uuid = const Uuid();

  PaymentRepositoryImpl(this._paymentsDao, this._billingRepository);

  @override
  Future<Result<Payment>> recordPayment({
    required String billId,
    required double amount,
    required PaymentMethod method,
  }) async {
    try {
      final payment = Payment(
        id: _uuid.v4(),
        billId: billId,
        amount: amount,
        method: method,
        paidAt: DateTime.now(),
      );
      await _paymentsDao.insertPayment(payment);
      return Success(payment);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<Payment>>> getPaymentsForBill(String billId) async {
    try {
      final payments = await _paymentsDao.getPaymentsForBill(billId);
      return Success(payments);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<double>> getOutstandingBalance(String billId) async {
    try {
      final billResult = await _billingRepository.getBillById(billId);
      if (billResult is Failure) {
        return Failure((billResult as Failure).failure);
      }
      final bill = (billResult as Success<Bill?>).value;
      if (bill == null) {
        return const Failure(NotFoundFailure('Bill not found.'));
      }
      final paid = await _paymentsDao.sumPaymentsForBill(billId);
      final outstanding = (bill.total - paid).clamp(0.0, double.infinity);
      return Success(outstanding);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }
}
