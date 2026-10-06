import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../appointments/domain/appointment.dart';
import '../../../appointments/domain/appointment_repository.dart';
import '../../../reports/domain/report_repository.dart';
import '../../../reports/domain/customer_balance.dart';
import '../../../settings/domain/settings_repository.dart';
import '../../../core/utils/result.dart';

part 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  final AppointmentRepository _appointmentRepository;
  final ReportRepository _reportRepository;
  final SettingsRepository _settingsRepository;

  HomeCubit({
    required AppointmentRepository appointmentRepository,
    required ReportRepository reportRepository,
    required SettingsRepository settingsRepository,
  })  : _appointmentRepository = appointmentRepository,
        _reportRepository = reportRepository,
        _settingsRepository = settingsRepository,
        super(const HomeState.initial());

  Future<void> loadData() async {
    emit(const HomeState.loading());

    try {
      // Load today's appointments
      final today = DateTime.now();
      final todayAppointmentsResult = await _appointmentRepository.getAppointmentsForDate(today);
      final todayAppointments = switch (todayAppointmentsResult) {
        Success(value: final value) => value,
        Failure() => <Appointment>[],
      };

      // Load outstanding balance summary
      final customersWithBalanceResult = await _reportRepository.getCustomersWithBalance();
      final customersWithBalance = switch (customersWithBalanceResult) {
        Success(value: final value) => value,
        Failure() => <CustomerBalance>[],
      };
      final totalOutstanding = customersWithBalance.fold<double>(
        0,
        (sum, customerBalance) => sum + customerBalance.outstandingAmount,
      );

      // Load settings for parlour name
      final settingsResult = await _settingsRepository.getSettings();
      String parlourName = 'Parlour Management';
      if (settingsResult is Success) {
        parlourName = settingsResult.value.parlourName;
      }

      emit(HomeState.loaded(
        todayAppointments: todayAppointments,
        totalOutstanding: totalOutstanding,
        parlourName: parlourName,
        customersWithBalance: customersWithBalance,
      ));
    } catch (e) {
      emit(HomeState.error(e.toString()));
    }
  }

  void refresh() {
    loadData();
  }
}