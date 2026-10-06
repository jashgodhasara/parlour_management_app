import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/result.dart';
import '../domain/customer.dart';
import 'customer_list_cubit.dart';

class CustomerListScreen extends StatelessWidget {
  const CustomerListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<CustomerListCubit>(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Customers'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'More options',
                onSelected: (value) {
                  if (value == 'delete_all') {
                    _confirmDeleteAll(context);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete_all',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep_outlined, color: Colors.red),
                        SizedBox(width: 12),
                        Text('Delete All Clients',
                            style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: const _CustomerListBody(),
          floatingActionButton: FloatingActionButton(
            onPressed: () => context.push('/customers/new'),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final state = context.read<CustomerListCubit>().state;
    final count = state is CustomerListStateLoaded
        ? state.customers.length
        : 0;

    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No clients to delete')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.red, size: 40),
        title: const Text('Delete all clients?'),
        content: Text(
          'This will permanently delete all $count client${count == 1 ? '' : 's'}.\n\nThis action cannot be undone.',
        ),
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
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final result =
        await context.read<CustomerListCubit>().deleteAllCustomers();

    switch (result) {
      case Success<void>():
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'All $count client${count == 1 ? '' : 's'} deleted'),
            backgroundColor: Colors.green,
          ),
        );
      case Failure<void>(failure: final failure):
        messenger.showSnackBar(
          SnackBar(
            content: Text(failure.message),
            backgroundColor: Colors.red,
          ),
        );
    }
  }
}

class _CustomerListBody extends StatelessWidget {
  const _CustomerListBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(context),
        Expanded(
          child: _buildCustomerList(context),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search by name or phone...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onChanged: (query) {
          context.read<CustomerListCubit>().updateSearchQuery(query);
        },
      ),
    );
  }

  Widget _buildCustomerList(BuildContext context) {
    return BlocBuilder<CustomerListCubit, CustomerListState>(
      builder: (context, state) {
        return switch (state) {
          CustomerListStateLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          CustomerListStateError(message: final message) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $message'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<CustomerListCubit>().refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          CustomerListStateLoaded(customers: final customers) =>
            _buildCustomerListView(customers, context),
          CustomerListStateInitial() => const Center(
              child: CircularProgressIndicator(),
            ),
        };
      },
    );
  }

  Widget _buildCustomerListView(
      List<Customer> customers, BuildContext context) {
    if (customers.isEmpty) {
      return const Center(
        child: Text(
          'No customers found',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => context.read<CustomerListCubit>().refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: customers.length,
        itemBuilder: (context, index) {
          final customer = customers[index];
          return _CustomerTile(customer: customer);
        },
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final Customer customer;

  const _CustomerTile({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: _buildCustomerAvatar(),
        title: Text(
          customer.fullName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(customer.phoneNumber),
        trailing: PopupMenuButton<String>(
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
        onTap: () => context.push('/customers/${customer.id}'),
      ),
    );
  }

  Future<void> _deleteCustomer(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete customer?'),
        content: Text('Delete ${customer.fullName} from your customer list?'),
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
    final result =
        await context.read<CustomerListCubit>().deleteCustomer(customer.id);

    switch (result) {
      case Success<void>():
        messenger.showSnackBar(
          SnackBar(content: Text('${customer.fullName} deleted')),
        );
      case Failure<void>(failure: final failure):
        messenger.showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
    }
  }

  Widget _buildCustomerAvatar() {
    if (customer.photoPath != null && customer.photoPath!.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: NetworkImage(customer.photoPath!),
        radius: 20,
      );
    }

    return CircleAvatar(
      backgroundColor: Colors.blue[100],
      radius: 20,
      child: Text(
        customer.fullName.isNotEmpty ? customer.fullName[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.blue,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
