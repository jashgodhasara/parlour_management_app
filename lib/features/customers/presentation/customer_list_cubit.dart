import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/utils/result.dart';
import '../domain/customer.dart';
import '../domain/use_cases/delete_all_customers_use_case.dart';
import '../domain/use_cases/delete_customer_use_case.dart';
import '../domain/use_cases/search_customers_use_case.dart';
import '../domain/use_cases/get_customer_by_id_use_case.dart';

part 'customer_list_state.dart';

class CustomerListCubit extends Cubit<CustomerListState> {
  final SearchCustomersUseCase _searchCustomersUseCase;
  final GetCustomerByIdUseCase _getCustomerByIdUseCase;
  final DeleteCustomerUseCase _deleteCustomerUseCase;
  final DeleteAllCustomersUseCase _deleteAllCustomersUseCase;
  Timer? _searchDebounceTimer;
  String _currentSearchQuery = '';

  CustomerListCubit({
    required SearchCustomersUseCase searchCustomersUseCase,
    required GetCustomerByIdUseCase getCustomerByIdUseCase,
    required DeleteCustomerUseCase deleteCustomerUseCase,
    required DeleteAllCustomersUseCase deleteAllCustomersUseCase,
  })  : _searchCustomersUseCase = searchCustomersUseCase,
        _getCustomerByIdUseCase = getCustomerByIdUseCase,
        _deleteCustomerUseCase = deleteCustomerUseCase,
        _deleteAllCustomersUseCase = deleteAllCustomersUseCase,
        super(const CustomerListStateInitial()) {
    loadCustomers();
  }

  Future<void> loadCustomers() async {
    emit(const CustomerListStateLoading());
    await _performSearch('');
  }

  void updateSearchQuery(String query) {
    _currentSearchQuery = query;

    // Cancel previous timer
    _searchDebounceTimer?.cancel();

    // Start new debounce timer
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(_currentSearchQuery);
    });
  }

  Future<void> _performSearch(String query) async {
    if (state is! CustomerListStateLoading) {
      emit(CustomerListStateLoading(searchQuery: query));
    }

    final result = await _searchCustomersUseCase(query.trim());
    switch (result) {
      case Success(value: final customers):
        emit(CustomerListStateLoaded(
          customers: customers,
          searchQuery: query,
        ));
      case Failure(failure: final failure):
        emit(CustomerListStateError(failure.message, searchQuery: query));
    }
  }

  Future<void> refresh() async {
    await _performSearch(state.searchQuery);
  }

  Future<Customer?> getCustomerById(String id) async {
    final result = await _getCustomerByIdUseCase(id);
    return switch (result) {
      Success(value: final customer) => customer,
      Failure() => null,
    };
  }

  Future<Result<void>> deleteCustomer(String id) async {
    final result = await _deleteCustomerUseCase(id);
    if (result is Success<void>) {
      await _performSearch(_currentSearchQuery);
    }

    return result;
  }

  Future<Result<void>> deleteAllCustomers() async {
    final result = await _deleteAllCustomersUseCase();
    if (result is Success<void>) {
      await _performSearch(_currentSearchQuery);
    }
    return result;
  }

  @override
  Future<void> close() {
    _searchDebounceTimer?.cancel();
    return super.close();
  }
}
