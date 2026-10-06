import '../../../../core/utils/result.dart';
import '../customer.dart';
import '../customer_repository.dart';

class UpdateCustomerUseCase {
  final CustomerRepository _repository;
  UpdateCustomerUseCase(this._repository);

  Future<Result<Customer>> call(Customer customer) async {
    if (customer.fullName.trim().isEmpty) {
      return Failure(const InvalidServiceFailure('Customer name cannot be empty.'));
    }
    return _repository.updateCustomer(customer);
  }
}
