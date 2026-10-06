import '../domain/customer.dart';

/// In-memory implementation of customer data access.
/// Replace with Drift DAO once build_runner is run.
class CustomersDao {
  final Map<String, Customer> _store = {};

  Future<void> insertCustomer(Customer customer) async {
    _store[customer.id] = customer;
  }

  Future<void> updateCustomer(Customer customer) async {
    _store[customer.id] = customer;
  }

  Future<bool> deleteCustomer(String id) async {
    return _store.remove(id) != null;
  }

  Future<Customer?> findById(String id) async {
    return _store[id];
  }

  Future<Customer?> findByPhone(String phone) async {
    try {
      return _store.values.firstWhere((c) => c.phoneNumber == phone);
    } catch (_) {
      return null;
    }
  }

  Future<List<Customer>> searchByNameOrPhone(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return _store.values.toList();
    return _store.values
        .where((c) =>
            c.fullName.toLowerCase().contains(q) || c.phoneNumber.contains(q))
        .toList();
  }

  Stream<List<Customer>> watchAllCustomers() async* {
    yield _store.values.toList();
  }

  Future<List<Customer>> getAllCustomers() async {
    return _store.values.toList();
  }

  /// Clears all customers from the in-memory store.
  void clear() => _store.clear();
}
