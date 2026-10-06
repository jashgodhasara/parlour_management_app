import '../../../../core/utils/result.dart';
import '../appointment.dart';
import '../appointment_repository.dart';

class UpdateAppointmentUseCase {
  final AppointmentRepository _repository;
  UpdateAppointmentUseCase(this._repository);

  Future<Result<Appointment>> call(Appointment appointment, {bool ignoreOverlap = false}) async {
    if (!ignoreOverlap) {
      final overlapResult = await _repository.hasOverlap(
        appointment.scheduledAt,
        appointment.scheduledAt,
        appointment.durationMinutes,
        excludeId: appointment.id,
      );
      if (overlapResult is Success<bool> && (overlapResult as Success<bool>).value) {
        return Failure(const AppointmentOverlapFailure());
      }
    }
    return _repository.updateAppointment(appointment);
  }
}
