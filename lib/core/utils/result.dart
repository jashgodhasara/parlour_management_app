/// A simple Result type for representing success or failure.
sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

final class Failure<T> extends Result<T> {
  final AppFailure failure;
  const Failure(this.failure);
}

/// Base class for all application failures.
sealed class AppFailure {
  final String message;
  const AppFailure(this.message);
}

final class DuplicatePhoneFailure extends AppFailure {
  const DuplicatePhoneFailure()
      : super('A customer with this phone number already exists.');
}

final class InvalidServiceFailure extends AppFailure {
  const InvalidServiceFailure([String? msg])
      : super(msg ?? 'Service name cannot be empty and price must be ₹0 or more.');
}

final class AppointmentOverlapFailure extends AppFailure {
  const AppointmentOverlapFailure()
      : super('This time slot overlaps with an existing appointment.');
}

final class EmptyBillFailure extends AppFailure {
  const EmptyBillFailure()
      : super('Please add at least one service before finalising.');
}

final class OverpaymentFailure extends AppFailure {
  final double outstanding;
  const OverpaymentFailure(this.outstanding)
      : super('Payment amount exceeds the outstanding balance.');
}

final class DatabaseFailure extends AppFailure {
  const DatabaseFailure([String? msg])
      : super(msg ?? 'Something went wrong saving your data. Please try again.');
}

final class BackupFailure extends AppFailure {
  const BackupFailure([String? msg])
      : super(msg ?? 'Backup to Google Drive failed. Check your internet connection.');
}

final class NotFoundFailure extends AppFailure {
  const NotFoundFailure([String? msg]) : super(msg ?? 'Record not found.');
}
