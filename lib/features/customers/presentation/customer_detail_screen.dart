import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/date_helpers.dart';
import '../../../../core/utils/result.dart';
import '../../billing/domain/bill.dart';
import '../../billing/domain/billing_repository.dart';
import '../../payments/domain/use_cases/get_outstanding_balance_use_case.dart';
import '../domain/customer.dart';
import '../domain/use_cases/delete_customer_use_case.dart';
import '../domain/use_cases/get_customer_by_id_use_case.dart';
import 'customer_detail_cubit.dart';

class CustomerDetailScreen extends StatelessWidget {
  final String customerId;

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CustomerDetailCubit(
        customerId: customerId,
        getCustomerByIdUseCase: sl<GetCustomerByIdUseCase>(),
        getOutstandingBalanceUseCase: sl<GetOutstandingBalanceUseCase>(),
        billingRepository: sl<BillingRepository>(),
        deleteCustomerUseCase: sl<DeleteCustomerUseCase>(),
      ),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Customer Details'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => context.push('/customers/$customerId/edit'),
                tooltip: 'Edit',
              ),
              PopupMenuButton<String>(
                tooltip: 'Customer options',
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteCustomer(context);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red),
                        SizedBox(width: 12),
                        Text('Delete'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: const _CustomerDetailBody(),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () =>
                context.push('/billing/new?customerId=$customerId'),
            icon: const Icon(Icons.receipt),
            label: const Text('New Bill'),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteCustomer(BuildContext context) async {
    final state = context.read<CustomerDetailCubit>().state;
    final customerName = state is CustomerDetailStateLoaded
        ? state.customer.fullName
        : 'this customer';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete customer?'),
        content: Text('Delete $customerName from your customer list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final result = await context.read<CustomerDetailCubit>().deleteCustomer();

    switch (result) {
      case Success<void>():
        messenger.showSnackBar(
          SnackBar(content: Text('$customerName deleted')),
        );
        router.go('/customers');
      case Failure<void>(failure: final failure):
        messenger.showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
    }
  }
}

class _CustomerDetailBody extends StatelessWidget {
  const _CustomerDetailBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CustomerDetailCubit, CustomerDetailState>(
      builder: (context, state) {
        return switch (state) {
          CustomerDetailStateInitial() => const Center(
              child: CircularProgressIndicator(),
            ),
          CustomerDetailStateLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          CustomerDetailStateError(message: final message) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $message',
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<CustomerDetailCubit>().refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          CustomerDetailStateLoaded(
            customer: final customer,
            outstandingBalance: final outstandingBalance,
            visitHistory: final visitHistory,
          ) =>
            _buildLoadedContent(
                context, customer, outstandingBalance, visitHistory),
        };
      },
    );
  }

  Widget _buildLoadedContent(
    BuildContext context,
    Customer customer,
    double outstandingBalance,
    List<Bill> visitHistory,
  ) {
    return RefreshIndicator(
      onRefresh: () async => context.read<CustomerDetailCubit>().refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCustomerHeader(customer),
          const SizedBox(height: 24),
          if (outstandingBalance > 0)
            _buildOutstandingBalanceBanner(outstandingBalance),
          if (outstandingBalance > 0) const SizedBox(height: 24),
          _buildVisitHistorySection(visitHistory, context),
        ],
      ),
    );
  }

  Widget _buildCustomerHeader(Customer customer) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildCustomerAvatar(customer),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.fullName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        customer.phoneNumber,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (customer.notes != null && customer.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Notes:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                customer.notes!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Member since ${DateHelpers.formatDate(customer.createdAt)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerAvatar(Customer customer) {
    if (customer.photoPath != null && customer.photoPath!.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: NetworkImage(customer.photoPath!),
        radius: 40,
      );
    }

    return CircleAvatar(
      backgroundColor: Colors.blue[100],
      radius: 40,
      child: Text(
        customer.fullName.isNotEmpty ? customer.fullName[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 32,
          color: Colors.blue,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildOutstandingBalanceBanner(double outstandingBalance) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Outstanding Balance',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  CurrencyFormatter.format(outstandingBalance),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitHistorySection(
      List<Bill> visitHistory, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Visit History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (visitHistory.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No visit history yet',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else
          Column(
            children:
                visitHistory.map((bill) => _VisitTile(bill: bill)).toList(),
          ),
      ],
    );
  }
}

class _VisitTile extends StatelessWidget {
  final Bill bill;

  const _VisitTile({required this.bill});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Status icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _getStatusColor(bill.status),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getStatusIcon(bill.status),
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            // Bill info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateHelpers.formatDate(bill.visitDate),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Total: ${CurrencyFormatter.format(bill.total)}'),
                  const SizedBox(height: 2),
                  _StatusChip(status: bill.status),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // View Bill button
            OutlinedButton.icon(
              onPressed: () => context.push('/billing/${bill.id}'),
              icon: const Icon(Icons.receipt_long, size: 16),
              label: const Text('View Bill'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(BillStatus status) {
    return switch (status) {
      BillStatus.draft => Colors.grey,
      BillStatus.finalised => Colors.blue,
      BillStatus.paid => Colors.green,
    };
  }

  IconData _getStatusIcon(BillStatus status) {
    return switch (status) {
      BillStatus.draft => Icons.drafts,
      BillStatus.finalised => Icons.receipt,
      BillStatus.paid => Icons.check_circle,
    };
  }
}

class _StatusChip extends StatelessWidget {
  final BillStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      BillStatus.draft => ('Draft', Colors.grey),
      BillStatus.finalised => ('Finalised', Colors.blue),
      BillStatus.paid => ('Paid', Colors.green),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
