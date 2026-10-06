import '../../../../core/utils/result.dart';
import '../customer_repository.dart';

class DeleteCustomerUseCase {
  final CustomerRepository _repository;

  DeleteCustomerUseCase(this._repository);

  Future<Result<void>> call(String id) async {
    if (id.trim().isEmpty) {
      return const Failure(NotFoundFailure('Customer not found.'));
    }

    return _repository.deleteCustomer(id);
  }
}
