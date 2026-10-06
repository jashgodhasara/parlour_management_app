import '../../../core/utils/result.dart';
import 'bill.dart';

abstract class BillingRepository {
  Future<Result<Bill>> createBill({
    required String customerId,
    required List<String> serviceIds,
    required double subtotal,
    required double discountAmount,
    DiscountType? discountType,
    required double total,
    String? appointmentId,
  });
  Future<Result<Bill>> finaliseBill(String billId);
  Future<Result<Bill>> markAsPaid(String billId);
  Future<Result<void>> deleteBill(String id);
  Future<Result<void>> deleteAllBills();
  Future<Result<Bill?>> getBillById(String id);
  Future<Result<List<Bill>>> getBillsForCustomer(String customerId);
  Future<Result<List<Bill>>> getVisitHistory(String customerId);

  /// Update the price of a single line item and recalculate bill totals.
  Future<Result<Bill>> updateLineItemPrice({
    required String billId,
    required String serviceId,
    required double newPrice,
  });
}
