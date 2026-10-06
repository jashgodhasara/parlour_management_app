import '../../../../core/utils/result.dart';
import '../customer.dart';
import '../customer_repository.dart';

class SearchCustomersUseCase {
  final CustomerRepository _repository;
  SearchCustomersUseCase(this._repository);

  Future<Result<List<Customer>>> call(String query) async {
    return _repository.searchCustomers(query.toLowerCase().trim());
  }
}
