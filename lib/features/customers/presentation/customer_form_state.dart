import 'package:equatable/equatable.dart';

import '../domain/customer.dart';

part of 'customer_form_cubit.dart';

sealed class CustomerFormState extends Equatable {
  const CustomerFormState();

  @override
  List<Object?> get props => [];
}

class CustomerFormStateInitial extends CustomerFormState {
  const CustomerFormStateInitial();
}

class CustomerFormStateLoading extends CustomerFormState {
  const CustomerFormStateLoading();
}

class CustomerFormStateCreating extends CustomerFormState {
  final String fullName;
  final String phoneNumber;
  final String notes;
  final String photoPath;

  const CustomerFormStateCreating({
    this.fullName = '',
    this.phoneNumber = '',
    this.notes = '',
    this.photoPath = '',
  });

  CustomerFormStateCreating copyWith({
    String? fullName,
    String? phoneNumber,
    String? notes,
    String? photoPath,
  }) {
    return CustomerFormStateCreating(
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      notes: notes ?? this.notes,
      photoPath: photoPath ?? this.photoPath,
    );
  }

  @override
  List<Object?> get props => [fullName, phoneNumber, notes, photoPath];
}

class CustomerFormStateEditing extends CustomerFormState {
  final Customer customer;
  final String fullName;
  final String phoneNumber;
  final String notes;
  final String photoPath;

  const CustomerFormStateEditing({
    required this.customer,
    required this.fullName,
    required this.phoneNumber,
    required this.notes,
    required this.photoPath,
  });

  CustomerFormStateEditing copyWith({
    String? fullName,
    String? phoneNumber,
    String? notes,
    String? photoPath,
  }) {
    return CustomerFormStateEditing(
      customer: customer,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      notes: notes ?? this.notes,
      photoPath: photoPath ?? this.photoPath,
    );
  }

  @override
  List<Object?> get props => [customer, fullName, phoneNumber, notes, photoPath];
}

class CustomerFormStateSaving extends CustomerFormState {
  const CustomerFormStateSaving();
}

class CustomerFormStateSaved extends CustomerFormState {
  final Customer customer;

  const CustomerFormStateSaved(this.customer);

  @override
  List<Object?> get props => [customer];
}

class CustomerFormStateError extends CustomerFormState {
  final String message;

  const CustomerFormStateError(this.message);

  @override
  List<Object?> get props => [message];
}

class CustomerFormStateValidationError extends CustomerFormState {
  final String message;

  const CustomerFormStateValidationError(this.message);

  @override
  List<Object?> get props => [message];
}

class CustomerFormStateDuplicatePhoneError extends CustomerFormState {
  const CustomerFormStateDuplicatePhoneError();
}