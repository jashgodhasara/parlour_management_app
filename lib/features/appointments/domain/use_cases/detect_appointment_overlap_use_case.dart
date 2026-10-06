import '../../../../core/utils/result.dart';
import '../appointment_repository.dart';

class DetectAppointmentOverlapUseCase {
  final AppointmentRepository _repository;
  DetectAppointmentOverlapUseCase(this._repository);

  Future<Result<bool>> call(
    DateTime date,
    DateTime startTime,
    int durationMinutes, {
    String? excludeId,
  }) async {
    return _repository.hasOverlap(date, startTime, durationMinutes, excludeId: excludeId);
  }
}
