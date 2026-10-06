abstract class NotificationService {
  Future<void> scheduleReminder(String id, String title, DateTime triggerAt);
  Future<void> cancelReminder(String id);
  Future<void> cancelAll();
}
