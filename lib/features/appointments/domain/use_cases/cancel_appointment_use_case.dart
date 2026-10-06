import '../../../../core/utils/result.dart';
import '../appointment_repository.dart';

class CancelAppointmentUseCase {
  final AppointmentRepository _repository;
  CancelAppointmentUseCase(this._repository);

  Future<Result<void>> call(String appointmentId) async {
    return _repository.cancelAppointment(appointmentId);
  }
}
