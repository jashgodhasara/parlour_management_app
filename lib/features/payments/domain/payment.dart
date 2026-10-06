enum PaymentMethod { cash, online }

class Payment {
  final String id;
  final String billId;
  final double amount;
  final PaymentMethod method;
  final DateTime paidAt;

  const Payment({
    required this.id,
    required this.billId,
    required this.amount,
    required this.method,
    required this.paidAt,
  });

  Payment copyWith({
    String? id,
    String? billId,
    double? amount,
    PaymentMethod? method,
    DateTime? paidAt,
  }) {
    return Payment(
      id: id ?? this.id,
      billId: billId ?? this.billId,
      amount: amount ?? this.amount,
      method: method ?? this.method,
      paidAt: paidAt ?? this.paidAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Payment && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Payment(id: $id, billId: $billId, amount: $amount, method: $method)';
}
