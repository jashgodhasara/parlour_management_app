import 'package:equatable/equatable.dart';

import '../../../appointments/domain/appointment.dart';
import '../../../reports/domain/customer_balance.dart';

part of 'home_cubit.dart';

sealed class HomeState extends Equatable {
  const HomeState();

  @override
  List<Object?> get props => [];
}

class HomeStateInitial extends HomeState {
  const HomeStateInitial();
}

class HomeStateLoading extends HomeState {
  const HomeStateLoading();
}

class HomeStateLoaded extends HomeState {
  final List<Appointment> todayAppointments;
  final double totalOutstanding;
  final String parlourName;
  final List<CustomerBalance> customersWithBalance;

  const HomeStateLoaded({
    required this.todayAppointments,
    required this.totalOutstanding,
    required this.parlourName,
    required this.customersWithBalance,
  });

  @override
  List<Object?> get props => [
        todayAppointments,
        totalOutstanding,
        parlourName,
        customersWithBalance,
      ];
}

class HomeStateError extends HomeState {
  final String message;

  const HomeStateError(this.message);

  @override
  List<Object?> get props => [message];
}