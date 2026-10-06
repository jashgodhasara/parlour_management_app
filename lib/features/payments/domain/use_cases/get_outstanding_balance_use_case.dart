import '../../../../core/utils/result.dart';
import '../payment_repository.dart';

class GetOutstandingBalanceUseCase {
  final PaymentRepository _repository;
  GetOutstandingBalanceUseCase(this._repository);

  Future<Result<double>> call(String billId) async {
    return _repository.getOutstandingBalance(billId);
  }
}
