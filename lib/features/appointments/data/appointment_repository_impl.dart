import 'package:uuid/uuid.dart';
import '../../../../core/utils/result.dart';
import '../../services/domain/service.dart';
import '../../services/data/services_dao.dart';
import '../domain/appointment.dart';
import '../domain/appointment_repository.dart';
import 'appointments_dao.dart';

class AppointmentRepositoryImpl implements AppointmentRepository {
  final AppointmentsDao _dao;
  final ServicesDao _servicesDao;
  final _uuid = const Uuid();

  AppointmentRepositoryImpl(this._dao, this._servicesDao);

  @override
  Future<Result<Appointment>> createAppointment({
    required String customerId,
    required List<String> serviceIds,
    required DateTime scheduledAt,
    required int durationMinutes,
  }) async {
    try {
      final services = <ParlourService>[];
      for (final id in serviceIds) {
        final s = await _servicesDao.findById(id);
        if (s != null) services.add(s);
      }
      final appointment = Appointment(
        id: _uuid.v4(),
        customerId: customerId,
        scheduledAt: scheduledAt,
        durationMinutes: durationMinutes,
        status: AppointmentStatus.scheduled,
        services: services,
      );
      await _dao.insertAppointment(appointment);
      return Success(appointment);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<Appointment>> updateAppointment(Appointment appointment) async {
    try {
      await _dao.updateAppointment(appointment);
      return Success(appointment);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> cancelAppointment(String id) async {
    try {
      await _dao.cancelAppointment(id);
      return const Success(null);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<Appointment>>> getAppointmentsForDate(DateTime date) async {
    try {
      final results = await _dao.getAppointmentsForDate(date);
      return Success(results);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<Appointment>>> getAppointmentsForWeek(DateTime weekStart) async {
    try {
      final results = await _dao.getAppointmentsForWeek(weekStart);
      return Success(results);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<bool>> hasOverlap(
    DateTime date,
    DateTime startTime,
    int durationMinutes, {
    String? excludeId,
  }) async {
    try {
      final appointments = await _dao.getAppointmentsForDate(date);
      final endTime = startTime.add(Duration(minutes: durationMinutes));
      for (final appt in appointments) {
        if (excludeId != null && appt.id == excludeId) continue;
        final apptEnd = appt.endTime;
        // Overlap: start < apptEnd AND end > apptStart
        if (startTime.isBefore(apptEnd) && endTime.isAfter(appt.scheduledAt)) {
          return const Success(true);
        }
      }
      return const Success(false);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }
}
