import '../../../../core/utils/result.dart';
import '../bill.dart';
import '../billing_repository.dart';

class FinaliseBillUseCase {
  final BillingRepository _repository;
  FinaliseBillUseCase(this._repository);

  Future<Result<Bill>> call(String billId) async {
    return _repository.finaliseBill(billId);
  }
}
