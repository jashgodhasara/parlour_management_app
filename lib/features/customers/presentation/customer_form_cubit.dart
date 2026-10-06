import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/utils/result.dart';
import '../domain/customer.dart';
import '../domain/use_cases/create_customer_use_case.dart';
import '../domain/use_cases/update_customer_use_case.dart';
import '../domain/use_cases/get_customer_by_id_use_case.dart';

part 'customer_form_state.dart';

class CustomerFormCubit extends Cubit<CustomerFormState> {
  final CreateCustomerUseCase _createCustomerUseCase;
  final UpdateCustomerUseCase _updateCustomerUseCase;
  final GetCustomerByIdUseCase _getCustomerByIdUseCase;
  final String? _customerId;

  CustomerFormCubit({
    required CreateCustomerUseCase createCustomerUseCase,
    required UpdateCustomerUseCase updateCustomerUseCase,
    required GetCustomerByIdUseCase getCustomerByIdUseCase,
    String? customerId,
  })  : _createCustomerUseCase = createCustomerUseCase,
        _updateCustomerUseCase = updateCustomerUseCase,
        _getCustomerByIdUseCase = getCustomerByIdUseCase,
        _customerId = customerId,
        super(const CustomerFormState.initial()) {
    if (customerId != null) {
      loadCustomer(customerId);
    }
  }

  Future<void> loadCustomer(String id) async {
    emit(const CustomerFormState.loading());
    
    final result = await _getCustomerByIdUseCase(id);
    switch (result) {
      case Success(value: final customer):
        emit(CustomerFormState.editing(
          customer: customer,
          fullName: customer.fullName,
          phoneNumber: customer.phoneNumber,
          notes: customer.notes ?? '',
          photoPath: customer.photoPath ?? '',
        ));
      case Failure(failure: final failure):
        emit(CustomerFormState.error(failure.message));
    }
  }

  void updateFullName(String fullName) {
    final currentState = state;
    if (currentState is CustomerFormStateEditing) {
      emit(currentState.copyWith(fullName: fullName));
    } else if (currentState is CustomerFormStateCreating) {
      emit(currentState.copyWith(fullName: fullName));
    }
  }

  void updatePhoneNumber(String phoneNumber) {
    final currentState = state;
    if (currentState is CustomerFormStateEditing) {
      emit(currentState.copyWith(phoneNumber: phoneNumber));
    } else if (currentState is CustomerFormStateCreating) {
      emit(currentState.copyWith(phoneNumber: phoneNumber));
    }
  }

  void updateNotes(String notes) {
    final currentState = state;
    if (currentState is CustomerFormStateEditing) {
      emit(currentState.copyWith(notes: notes));
    } else if (currentState is CustomerFormStateCreating) {
      emit(currentState.copyWith(notes: notes));
    }
  }

  void updatePhotoPath(String photoPath) {
    final currentState = state;
    if (currentState is CustomerFormStateEditing) {
      emit(currentState.copyWith(photoPath: photoPath));
    } else if (currentState is CustomerFormStateCreating) {
      emit(currentState.copyWith(photoPath: photoPath));
    }
  }

  Future<void> saveCustomer() async {
    final currentState = state;
    if (currentState is! CustomerFormStateEditing && 
        currentState is! CustomerFormStateCreating) {
      return;
    }

    emit(const CustomerFormState.saving());

    final fullName = currentState.fullName.trim();
    final phoneNumber = currentState.phoneNumber.trim();
    final notes = currentState.notes.trim();
    final photoPath = currentState.photoPath.trim();

    // Validate required fields
    if (fullName.isEmpty) {
      emit(CustomerFormState.validationError('Full name is required'));
      return;
    }

    if (phoneNumber.isEmpty) {
      emit(CustomerFormState.validationError('Phone number is required'));
      return;
    }

    Result<Customer> result;
    
    if (_customerId != null && currentState is CustomerFormStateEditing) {
      // Update existing customer
      final updatedCustomer = currentState.customer.copyWith(
        fullName: fullName,
        phoneNumber: phoneNumber,
        notes: notes.isNotEmpty ? notes : null,
        photoPath: photoPath.isNotEmpty ? photoPath : null,
      );
      
      result = await _updateCustomerUseCase(updatedCustomer);
    } else {
      // Create new customer
      result = await _createCustomerUseCase(
        fullName: fullName,
        phoneNumber: phoneNumber,
        notes: notes.isNotEmpty ? notes : null,
        photoPath: photoPath.isNotEmpty ? photoPath : null,
      );
    }

    switch (result) {
      case Success(value: final customer):
        emit(CustomerFormState.saved(customer));
      case Failure(failure: final failure):
        if (failure is DuplicatePhoneFailure) {
          emit(CustomerFormState.duplicatePhoneError());
        } else {
          emit(CustomerFormState.error(failure.message));
        }
    }
  }

  void reset() {
    if (_customerId != null) {
      final currentState = state;
      if (currentState is CustomerFormStateEditing) {
        emit(CustomerFormState.editing(
          customer: currentState.customer,
          fullName: currentState.customer.fullName,
          phoneNumber: currentState.customer.phoneNumber,
          notes: currentState.customer.notes ?? '',
          photoPath: currentState.customer.photoPath ?? '',
        ));
      }
    } else {
      emit(const CustomerFormState.creating());
    }
  }
}