import '../../../../core/utils/result.dart';
import '../customer.dart';
import '../customer_repository.dart';

class CreateCustomerUseCase {
  final CustomerRepository _repository;
  CreateCustomerUseCase(this._repository);

  Future<Result<Customer>> call({
    required String fullName,
    required String phoneNumber,
    String? notes,
    String? photoPath,
  }) async {
    // Validate inputs
    if (fullName.trim().isEmpty) {
      return Failure(const InvalidServiceFailure('Customer name cannot be empty.'));
    }
    if (phoneNumber.trim().isEmpty) {
      return Failure(const InvalidServiceFailure('Phone number cannot be empty.'));
    }

    // Check for duplicate phone
    final existingResult = await _repository.getCustomerByPhone(phoneNumber.trim());
    if (existingResult is Success<Customer?>) {
      if ((existingResult as Success<Customer?>).value != null) {
        return Failure(const DuplicatePhoneFailure());
      }
    }

    return _repository.createCustomer(
      fullName: fullName.trim(),
      phoneNumber: phoneNumber.trim(),
      notes: notes?.trim(),
      photoPath: photoPath,
    );
  }
}
