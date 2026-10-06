class StatementTransaction {
  final DateTime date;
  final String billId;
  final String customerName;
  final String customerPhone;
  final String services;
  final double billAmount;
  final double paidAmount;
  final double outstandingAmount;
  final String paymentMethods;

  const StatementTransaction({
    required this.date,
    required this.billId,
    required this.customerName,
    required this.customerPhone,
    required this.services,
    required this.billAmount,
    required this.paidAmount,
    required this.outstandingAmount,
    required this.paymentMethods,
  });
}
