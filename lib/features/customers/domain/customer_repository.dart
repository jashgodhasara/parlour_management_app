import '../../../core/utils/result.dart';
import '../../billing/domain/bill.dart';
import 'customer.dart';

abstract class CustomerRepository {
  Future<Result<Customer>> createCustomer({
    required String fullName,
    required String phoneNumber,
    String? notes,
    String? photoPath,
  });
  Future<Result<Customer>> updateCustomer(Customer customer);
  Future<Result<void>> deleteCustomer(String id);
  Future<Result<void>> deleteAllCustomers();
  Future<Result<List<Customer>>> searchCustomers(String query);
  Future<Result<Customer?>> getCustomerById(String id);
  Future<Result<Customer?>> getCustomerByPhone(String phone);
  Future<Result<List<Bill>>> getVisitHistory(String customerId);
  Stream<List<Customer>> watchCustomersWithBalance();
}
