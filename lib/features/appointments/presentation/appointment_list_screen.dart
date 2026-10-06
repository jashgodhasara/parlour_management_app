import 'package:flutter/material.dart';

class AppointmentListScreen extends StatelessWidget {
  const AppointmentListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
      ),
      body: const Center(
        child: Text('Appointment List Screen - Under Development'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/appointments/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}