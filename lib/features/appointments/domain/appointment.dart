import '../../services/domain/service.dart';

enum AppointmentStatus { scheduled, completed, cancelled }

class Appointment {
  final String id;
  final String customerId;
  final DateTime scheduledAt;
  final int durationMinutes;
  final AppointmentStatus status;
  final List<ParlourService> services;

  const Appointment({
    required this.id,
    required this.customerId,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.status,
    required this.services,
  });

  DateTime get endTime => scheduledAt.add(Duration(minutes: durationMinutes));

  Appointment copyWith({
    String? id,
    String? customerId,
    DateTime? scheduledAt,
    int? durationMinutes,
    AppointmentStatus? status,
    List<ParlourService>? services,
  }) {
    return Appointment(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      status: status ?? this.status,
      services: services ?? this.services,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Appointment && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Appointment(id: $id, customerId: $customerId, scheduledAt: $scheduledAt)';
}
