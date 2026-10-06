import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/utils/result.dart';
import '../../billing/domain/bill.dart';
import '../../billing/domain/billing_repository.dart';
import '../../payments/domain/use_cases/get_outstanding_balance_use_case.dart';
import '../domain/customer.dart';
import '../domain/use_cases/delete_customer_use_case.dart';
import '../domain/use_cases/get_customer_by_id_use_case.dart';

part 'customer_detail_state.dart';

class CustomerDetailCubit extends Cubit<CustomerDetailState> {
  final String customerId;
  final GetCustomerByIdUseCase _getCustomerByIdUseCase;
  final GetOutstandingBalanceUseCase _getOutstandingBalanceUseCase;
  final BillingRepository _billingRepository;
  final DeleteCustomerUseCase _deleteCustomerUseCase;

  CustomerDetailCubit({
    required this.customerId,
    required GetCustomerByIdUseCase getCustomerByIdUseCase,
    required GetOutstandingBalanceUseCase getOutstandingBalanceUseCase,
    required BillingRepository billingRepository,
    required DeleteCustomerUseCase deleteCustomerUseCase,
  })  : _getCustomerByIdUseCase = getCustomerByIdUseCase,
        _getOutstandingBalanceUseCase = getOutstandingBalanceUseCase,
        _billingRepository = billingRepository,
        _deleteCustomerUseCase = deleteCustomerUseCase,
        super(const CustomerDetailStateInitial()) {
    loadCustomer();
  }

  Future<void> loadCustomer() async {
    emit(const CustomerDetailStateLoading());

    try {
      final customerResult = await _getCustomerByIdUseCase(customerId);
      final Customer customer;
      switch (customerResult) {
        case Success(value: final foundCustomer):
          if (foundCustomer == null) {
            emit(const CustomerDetailStateError('Customer not found.'));
            return;
          }
          customer = foundCustomer;
        case Failure(failure: final failure):
          emit(CustomerDetailStateError(failure.message));
          return;
      }

      double outstandingBalance = 0.0;
      final billsResult =
          await _billingRepository.getBillsForCustomer(customerId);
      switch (billsResult) {
        case Success(value: final bills):
          for (final bill in bills) {
            final balanceResult = await _getOutstandingBalanceUseCase(bill.id);
            if (balanceResult case Success(value: final balance)) {
              outstandingBalance += balance;
            }
          }
        case Failure():
      }

      final visitHistoryResult =
          await _billingRepository.getVisitHistory(customerId);
      final visitHistory = switch (visitHistoryResult) {
        Success(value: final bills) => bills,
        Failure() => <Bill>[],
      };

      emit(CustomerDetailStateLoaded(
        customer: customer,
        outstandingBalance: outstandingBalance,
        visitHistory: visitHistory,
      ));
    } catch (e) {
      emit(CustomerDetailStateError(e.toString()));
    }
  }

  Future<void> refresh() async {
    await loadCustomer();
  }

  Future<Result<void>> deleteCustomer() {
    return _deleteCustomerUseCase(customerId);
  }
}
