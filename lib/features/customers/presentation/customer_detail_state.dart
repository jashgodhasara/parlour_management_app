part of 'customer_detail_cubit.dart';

sealed class CustomerDetailState extends Equatable {
  const CustomerDetailState();

  @override
  List<Object?> get props => [];
}

class CustomerDetailStateInitial extends CustomerDetailState {
  const CustomerDetailStateInitial();
}

class CustomerDetailStateLoading extends CustomerDetailState {
  const CustomerDetailStateLoading();
}

class CustomerDetailStateLoaded extends CustomerDetailState {
  final Customer customer;
  final double outstandingBalance;
  final List<Bill> visitHistory;

  const CustomerDetailStateLoaded({
    required this.customer,
    required this.outstandingBalance,
    required this.visitHistory,
  });

  @override
  List<Object?> get props => [customer, outstandingBalance, visitHistory];
}

class CustomerDetailStateError extends CustomerDetailState {
  final String message;

  const CustomerDetailStateError(this.message);

  @override
  List<Object?> get props => [message];
}
