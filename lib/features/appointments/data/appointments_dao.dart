import '../../../../core/utils/date_helpers.dart';
import '../domain/appointment.dart';

/// In-memory DAO for appointments.
class AppointmentsDao {
  final Map<String, Appointment> _store = {};

  Future<void> insertAppointment(Appointment appointment) async {
    _store[appointment.id] = appointment;
  }

  Future<void> updateAppointment(Appointment appointment) async {
    _store[appointment.id] = appointment;
  }

  Future<void> cancelAppointment(String id) async {
    final appt = _store[id];
    if (appt != null) {
      _store[id] = appt.copyWith(status: AppointmentStatus.cancelled);
    }
  }

  Future<List<Appointment>> getAppointmentsForDate(DateTime date) async {
    return _store.values
        .where((a) =>
            DateHelpers.isSameDay(a.scheduledAt, date) &&
            a.status != AppointmentStatus.cancelled)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  Future<List<Appointment>> getAppointmentsForWeek(DateTime weekStart) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    return _store.values
        .where((a) =>
            a.scheduledAt.isAfter(weekStart.subtract(const Duration(seconds: 1))) &&
            a.scheduledAt.isBefore(weekEnd) &&
            a.status != AppointmentStatus.cancelled)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  Future<Appointment?> findById(String id) async {
    return _store[id];
  }

  Future<List<Appointment>> getAllAppointments() async {
    return _store.values.toList();
  }

  /// Clears all appointments from the in-memory store.
  void clear() => _store.clear();
}
