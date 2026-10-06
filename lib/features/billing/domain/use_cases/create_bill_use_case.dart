import '../../../../core/utils/result.dart';
import '../bill.dart';
import '../billing_repository.dart';

class CreateBillUseCase {
  final BillingRepository _repository;
  CreateBillUseCase(this._repository);

  Future<Result<Bill>> call({
    required String customerId,
    required List<String> serviceIds,
    required double subtotal,
    required double discountAmount,
    DiscountType? discountType,
    required double total,
    String? appointmentId,
  }) async {
    if (serviceIds.isEmpty) {
      return const Failure(EmptyBillFailure());
    }

    return _repository.createBill(
      customerId: customerId,
      serviceIds: serviceIds,
      subtotal: subtotal,
      discountAmount: discountAmount,
      discountType: discountType,
      total: total,
      appointmentId: appointmentId,
    );
  }
}
