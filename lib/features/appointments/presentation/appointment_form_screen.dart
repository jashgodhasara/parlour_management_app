import 'package:flutter/material.dart';

class AppointmentFormScreen extends StatelessWidget {
  final String? appointmentId;

  const AppointmentFormScreen({
    super.key,
    this.appointmentId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(appointmentId == null ? 'New Appointment' : 'Edit Appointment'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (appointmentId != null) Text('Editing Appointment ID: $appointmentId'),
            const SizedBox(height: 16),
            const Text('Appointment Form Screen - Under Development'),
          ],
        ),
      ),
    );
  }
}