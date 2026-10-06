import '../appointment.dart';
import '../notification_service.dart';

class ScheduleNotificationUseCase {
  final NotificationService _notificationService;
  ScheduleNotificationUseCase(this._notificationService);

  Future<void> call(Appointment appointment) async {
    final triggerAt = appointment.scheduledAt.subtract(const Duration(minutes: 30));
    // Only schedule if trigger time is in the future
    if (triggerAt.isAfter(DateTime.now())) {
      await _notificationService.scheduleReminder(
        appointment.id,
        'Appointment reminder',
        triggerAt,
      );
    }
  }
}
