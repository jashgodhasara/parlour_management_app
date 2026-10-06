import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_selector/file_selector.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/app_router.dart';
import '../../../appointments/presentation/appointment_card.dart';
import '../../../backup/domain/backup_repository.dart';
import '../../../backup/domain/use_cases/export_data_use_case.dart';
import '../../../customers/domain/customer.dart';
import '../../../payments/domain/customer_balance.dart';
import '../../../../core/utils/result.dart';
import 'home_cubit.dart';
import 'home_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => context.read<HomeCubit>()..loadData(),
      child: Scaffold(
        appBar: _buildAppBar(context),
        body: _buildBody(context),
        floatingActionButton: _buildFloatingActionButton(context),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      title: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, state) {
          if (state is HomeStateLoaded) {
            return Text(state.parlourName);
          }
          return const Text('Parlour Management');
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        return RefreshIndicator(
          onRefresh: () async => context.read<HomeCubit>().refresh(),
          child: _buildContent(context, state),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, HomeState state) {
    if (state is HomeStateLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is HomeStateError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: ${state.message}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.read<HomeCubit>().refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state is HomeStateLoaded) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOutstandingSummaryCard(context, state),
          const SizedBox(height: 16),
          _buildBackupCard(context),
          const SizedBox(height: 24),
          _buildTodayAppointmentsSection(context, state),
          const SizedBox(height: 24),
          _buildOutstandingCustomersSection(context, state),
        ],
      );
    }

    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildOutstandingSummaryCard(BuildContext context, HomeStateLoaded state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Outstanding Balance',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '₹${state.totalOutstanding.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'From ${state.customersWithBalance.length} customer(s)',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayAppointmentsSection(BuildContext context, HomeStateLoaded state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Appointments",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (state.todayAppointments.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No appointments scheduled for today',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else
          Column(
            children: state.todayAppointments
                .map((appointment) => AppointmentCard(appointment: appointment))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildOutstandingCustomersSection(BuildContext context, HomeStateLoaded state) {
    if (state.customersWithBalance.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customers with Outstanding Balance',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: state.customersWithBalance
                  .take(5) // Show top 5
                  .map((customerBalance) => ListTile(
                        title: Text(customerBalance.customer.fullName),
                        subtitle: Text(customerBalance.customer.phoneNumber),
                        trailing: Text(
                          '₹${customerBalance.outstandingAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        onTap: () => context.push('/customers/${customerBalance.customer.id}'),
                      ))
                  .toList(),
            ),
          ),
        ),
        if (state.customersWithBalance.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push('/reports?tab=outstanding'),
                child: const Text('View All'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBackupCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.backup_outlined,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Data Backup',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareBackup(context),
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share Backup'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _importBackup(context),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Import Backup'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareBackup(BuildContext context) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final exportUseCase = sl<ExportDataUseCase>();
      final result = await exportUseCase();

      if (!context.mounted) return;
      Navigator.pop(context); // close loader

      if (result is Failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${(result as Failure).failure}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final json = (result as Success<String>).value;
      final dir = await getTemporaryDirectory();
      final fileName =
          'parlour_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(json);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Parlour Management Backup',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    try {
      const typeGroup = XTypeGroup(
        label: 'JSON Backup',
        extensions: ['json'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;

      // Show loading
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final jsonString = await file.readAsString();
      // Validate it's valid JSON
      jsonDecode(jsonString);

      final backupRepo = sl<BackupRepository>();
      final result = await backupRepo.restoreFromJson(jsonString);

      if (!context.mounted) return;
      Navigator.pop(context); // close loader

      if (result is Failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: ${(result as Failure).failure}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup imported successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh home
      context.read<HomeCubit>().refresh();
    } catch (e) {
      if (context.mounted) {
        try { Navigator.pop(context); } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildFloatingActionButton(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _showActionMenu(context),
      icon: const Icon(Icons.add),
      label: const Text('New'),
    );
  }

  void _showActionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('New Appointment'),
              onTap: () {
                Navigator.pop(context);
                context.push('/appointments/new');
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt),
              title: const Text('New Bill'),
              onTap: () {
                Navigator.pop(context);
                context.push('/billing/new');
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('New Customer'),
              onTap: () {
                Navigator.pop(context);
                context.push('/customers/new');
              },
            ),
          ],
        ),
      ),
    );
  }
}