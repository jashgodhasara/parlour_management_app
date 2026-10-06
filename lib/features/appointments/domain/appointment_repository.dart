import '../../../core/utils/result.dart';
import 'appointment.dart';

abstract class AppointmentRepository {
  Future<Result<Appointment>> createAppointment({
    required String customerId,
    required List<String> serviceIds,
    required DateTime scheduledAt,
    required int durationMinutes,
  });
  Future<Result<Appointment>> updateAppointment(Appointment appointment);
  Future<Result<void>> cancelAppointment(String id);
  Future<Result<List<Appointment>>> getAppointmentsForDate(DateTime date);
  Future<Result<List<Appointment>>> getAppointmentsForWeek(DateTime weekStart);
  Future<Result<bool>> hasOverlap(
    DateTime date,
    DateTime startTime,
    int durationMinutes, {
    String? excludeId,
  });
}
