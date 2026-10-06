import '../domain/bill.dart';

/// In-memory DAO for bills and bill line items.
/// Replace with Drift DAO once build_runner is run.
class BillsDao {
  final Map<String, Bill> _bills = {};
  final Map<String, List<BillLineItem>> _lineItems = {};

  Future<void> insertBill(Bill bill) async {
    _bills[bill.id] = bill;
  }

  Future<void> insertBillLineItems(
      String billId, List<BillLineItem> items) async {
    _lineItems[billId] = List.unmodifiable(items);
  }

  Future<void> updateBillStatus(String billId, BillStatus status) async {
    final bill = _bills[billId];
    if (bill != null) {
      _bills[billId] = bill.copyWith(status: status);
    }
  }

  Future<bool> deleteBill(String id) async {
    final deleted = _bills.remove(id) != null;
    _lineItems.remove(id);
    return deleted;
  }

  Future<Bill?> getBillById(String id) async {
    final bill = _bills[id];
    if (bill == null) return null;
    final items = _lineItems[id] ?? [];
    return bill.copyWith(lineItems: items);
  }

  Future<List<Bill>> getBillsForCustomer(String customerId) async {
    return _bills.values
        .where((b) => b.customerId == customerId)
        .map((b) => b.copyWith(lineItems: _lineItems[b.id] ?? []))
        .toList()
      ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
  }

  Future<List<Bill>> getAllBills() async {
    return _bills.values
        .map((b) => b.copyWith(lineItems: _lineItems[b.id] ?? []))
        .toList()
      ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
  }

  /// Clears all bills and line items from the in-memory store.
  void clear() {
    _bills.clear();
    _lineItems.clear();
  }

  /// Update the price of a specific line item and recalculate subtotal/total.
  Future<Bill?> updateLineItemPrice({
    required String billId,
    required String serviceId,
    required double newPrice,
  }) async {
    final bill = _bills[billId];
    final items = _lineItems[billId];
    if (bill == null || items == null) return null;

    // Update the matching line item's price.
    final updatedItems = items.map((item) {
      if (item.serviceId == serviceId) {
        return BillLineItem(
          serviceId: item.serviceId,
          serviceName: item.serviceName,
          servicePrice: newPrice,
        );
      }
      return item;
    }).toList();

    // Recalculate subtotal and total.
    final newSubtotal =
        updatedItems.fold<double>(0.0, (sum, i) => sum + i.servicePrice);
    double newTotal;
    if (bill.discountType == DiscountType.flat) {
      newTotal =
          (newSubtotal - bill.discountAmount).clamp(0.0, double.infinity);
    } else if (bill.discountType == DiscountType.percentage) {
      newTotal = newSubtotal * (1 - bill.discountAmount / 100);
    } else {
      newTotal = newSubtotal;
    }

    final updatedBill = bill.copyWith(
      subtotal: newSubtotal,
      total: newTotal,
      lineItems: updatedItems,
    );

    _bills[billId] = updatedBill;
    _lineItems[billId] = List.unmodifiable(updatedItems);
    return updatedBill;
  }
}
