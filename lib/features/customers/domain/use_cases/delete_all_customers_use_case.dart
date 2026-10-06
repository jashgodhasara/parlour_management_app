import '../../../../core/utils/result.dart';
import '../customer_repository.dart';

class DeleteAllCustomersUseCase {
  final CustomerRepository _repository;

  DeleteAllCustomersUseCase(this._repository);

  Future<Result<void>> call() => _repository.deleteAllCustomers();
}
