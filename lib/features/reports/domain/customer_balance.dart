class CustomerBalance {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final double outstandingBalance;

  const CustomerBalance({
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.outstandingBalance,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomerBalance &&
          runtimeType == other.runtimeType &&
          customerId == other.customerId &&
          outstandingBalance == other.outstandingBalance;

  @override
  int get hashCode => Object.hash(customerId, outstandingBalance);

  @override
  String toString() =>
      'CustomerBalance(customerId: $customerId, outstandingBalance: $outstandingBalance)';
}
