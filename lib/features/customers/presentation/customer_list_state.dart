part of 'customer_list_cubit.dart';

sealed class CustomerListState extends Equatable {
  final String searchQuery;

  const CustomerListState({required this.searchQuery});

  @override
  List<Object?> get props => [searchQuery];
}

class CustomerListStateInitial extends CustomerListState {
  const CustomerListStateInitial() : super(searchQuery: '');
}

class CustomerListStateLoading extends CustomerListState {
  const CustomerListStateLoading({String searchQuery = ''})
      : super(searchQuery: searchQuery);
}

class CustomerListStateLoaded extends CustomerListState {
  final List<Customer> customers;

  const CustomerListStateLoaded({
    required this.customers,
    String searchQuery = '',
  }) : super(searchQuery: searchQuery);

  @override
  List<Object?> get props => [customers, searchQuery];
}

class CustomerListStateError extends CustomerListState {
  final String message;

  const CustomerListStateError(this.message, {String searchQuery = ''})
      : super(searchQuery: searchQuery);

  @override
  List<Object?> get props => [message, searchQuery];
}
