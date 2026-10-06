import '../domain/notification_service.dart';

/// Stub implementation of NotificationService.
/// Replace with flutter_local_notifications implementation once Flutter SDK is available.
class NotificationServiceImpl implements NotificationService {
  final Map<String, _ScheduledNotification> _scheduled = {};

  @override
  Future<void> scheduleReminder(String id, String title, DateTime triggerAt) async {
    _scheduled[id] = _ScheduledNotification(id: id, title: title, triggerAt: triggerAt);
    // In production: use flutter_local_notifications to schedule an exact alarm
  }

  @override
  Future<void> cancelReminder(String id) async {
    _scheduled.remove(id);
    // In production: cancel the notification by id
  }

  @override
  Future<void> cancelAll() async {
    _scheduled.clear();
    // In production: cancel all scheduled notifications
  }

  /// For testing: check if a notification is scheduled
  bool isScheduled(String id) => _scheduled.containsKey(id);
  DateTime? getTriggerTime(String id) => _scheduled[id]?.triggerAt;
}

class _ScheduledNotification {
  final String id;
  final String title;
  final DateTime triggerAt;
  _ScheduledNotification({required this.id, required this.title, required this.triggerAt});
}
