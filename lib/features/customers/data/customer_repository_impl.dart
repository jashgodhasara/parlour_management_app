import '../../../../core/utils/result.dart';
import '../../billing/domain/bill.dart';
import '../domain/customer.dart';
import '../domain/customer_repository.dart';
import 'customers_dao.dart';
import 'package:uuid/uuid.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  final CustomersDao _dao;
  final _uuid = const Uuid();

  CustomerRepositoryImpl(this._dao);

  @override
  Future<Result<Customer>> createCustomer({
    required String fullName,
    required String phoneNumber,
    String? notes,
    String? photoPath,
  }) async {
    try {
      final now = DateTime.now();
      final customer = Customer(
        id: _uuid.v4(),
        fullName: fullName,
        phoneNumber: phoneNumber,
        notes: notes,
        photoPath: photoPath,
        createdAt: now,
        updatedAt: now,
      );
      await _dao.insertCustomer(customer);
      return Success(customer);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<Customer>> updateCustomer(Customer customer) async {
    try {
      final updated = customer.copyWith(updatedAt: DateTime.now());
      await _dao.updateCustomer(updated);
      return Success(updated);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteCustomer(String id) async {
    try {
      final deleted = await _dao.deleteCustomer(id);
      if (!deleted) {
        return const Failure(NotFoundFailure('Customer not found.'));
      }

      return const Success(null);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteAllCustomers() async {
    try {
      _dao.clear();
      return const Success(null);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<Customer>>> searchCustomers(String query) async {
    try {
      final results = await _dao.searchByNameOrPhone(query);
      return Success(results);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<Customer?>> getCustomerById(String id) async {
    try {
      final customer = await _dao.findById(id);
      return Success(customer);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<Customer?>> getCustomerByPhone(String phone) async {
    try {
      final customer = await _dao.findByPhone(phone);
      return Success(customer);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<Bill>>> getVisitHistory(String customerId) async {
    // Bills are managed by BillingRepository; return empty list here.
    // In a full implementation, inject BillingRepository or use a join query.
    return const Success([]);
  }

  @override
  Stream<List<Customer>> watchCustomersWithBalance() {
    return _dao.watchAllCustomers();
  }
}
