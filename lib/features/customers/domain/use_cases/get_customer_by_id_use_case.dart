import '../../../../core/utils/result.dart';
import '../customer.dart';
import '../customer_repository.dart';

class GetCustomerByIdUseCase {
  final CustomerRepository _repository;
  GetCustomerByIdUseCase(this._repository);

  Future<Result<Customer?>> call(String id) async {
    return _repository.getCustomerById(id);
  }
}
