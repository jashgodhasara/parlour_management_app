import '../../../../core/utils/result.dart';
import '../appointment.dart';
import '../appointment_repository.dart';

class CreateAppointmentUseCase {
  final AppointmentRepository _repository;
  CreateAppointmentUseCase(this._repository);

  Future<Result<Appointment>> call({
    required String customerId,
    required List<String> serviceIds,
    required DateTime scheduledAt,
    required int durationMinutes,
    bool ignoreOverlap = false,
  }) async {
    if (!ignoreOverlap) {
      final overlapResult = await _repository.hasOverlap(
        scheduledAt,
        scheduledAt,
        durationMinutes,
      );
      if (overlapResult is Success<bool> && (overlapResult as Success<bool>).value) {
        return Failure(const AppointmentOverlapFailure());
      }
    }
    return _repository.createAppointment(
      customerId: customerId,
      serviceIds: serviceIds,
      scheduledAt: scheduledAt,
      durationMinutes: durationMinutes,
    );
  }
}
