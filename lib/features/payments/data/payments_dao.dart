import '../domain/payment.dart';

/// In-memory DAO for payments.
/// Replace with Drift DAO once build_runner is run.
class PaymentsDao {
  final Map<String, Payment> _store = {};

  Future<void> insertPayment(Payment payment) async {
    _store[payment.id] = payment;
  }

  Future<List<Payment>> getPaymentsForBill(String billId) async {
    return _store.values
        .where((p) => p.billId == billId)
        .toList()
      ..sort((a, b) => a.paidAt.compareTo(b.paidAt));
  }

  Future<double> sumPaymentsForBill(String billId) async {
    return _store.values
        .where((p) => p.billId == billId)
        .fold<double>(0.0, (sum, p) => sum + p.amount);
  }

  /// Clears all payments from the in-memory store.
  void clear() => _store.clear();
}
