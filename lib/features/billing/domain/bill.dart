enum BillStatus { draft, finalised, paid }

enum DiscountType { flat, percentage }

class BillLineItem {
  final String serviceId;
  final String serviceName;
  final double servicePrice;

  const BillLineItem({
    required this.serviceId,
    required this.serviceName,
    required this.servicePrice,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillLineItem &&
          runtimeType == other.runtimeType &&
          serviceId == other.serviceId &&
          serviceName == other.serviceName &&
          servicePrice == other.servicePrice;

  @override
  int get hashCode => Object.hash(serviceId, serviceName, servicePrice);
}

class Bill {
  final String id;
  final String customerId;
  final String? appointmentId;
  final double subtotal;
  final double discountAmount;
  final DiscountType? discountType;
  final double total;
  final BillStatus status;
  final DateTime visitDate;
  final List<BillLineItem> lineItems;

  const Bill({
    required this.id,
    required this.customerId,
    this.appointmentId,
    required this.subtotal,
    required this.discountAmount,
    this.discountType,
    required this.total,
    required this.status,
    required this.visitDate,
    required this.lineItems,
  });

  Bill copyWith({
    String? id,
    String? customerId,
    String? appointmentId,
    double? subtotal,
    double? discountAmount,
    DiscountType? discountType,
    double? total,
    BillStatus? status,
    DateTime? visitDate,
    List<BillLineItem>? lineItems,
  }) {
    return Bill(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      appointmentId: appointmentId ?? this.appointmentId,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      discountType: discountType ?? this.discountType,
      total: total ?? this.total,
      status: status ?? this.status,
      visitDate: visitDate ?? this.visitDate,
      lineItems: lineItems ?? this.lineItems,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bill && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Bill(id: $id, customerId: $customerId, total: $total, status: $status)';
}
