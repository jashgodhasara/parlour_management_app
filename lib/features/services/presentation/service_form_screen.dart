import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/currency_formatter.dart';
import 'service_form_cubit.dart';
import 'service_form_state.dart';

class ServiceFormScreen extends StatelessWidget {
  final String? serviceId;

  const ServiceFormScreen({
    super.key,
    this.serviceId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<ServiceFormCubit>(param1: serviceId),
      child: Scaffold(
        appBar: AppBar(
          title: Text(serviceId == null ? 'New Service' : 'Edit Service'),
        ),
        body: const _ServiceFormBody(),
      ),
    );
  }
}

class _ServiceFormBody extends StatelessWidget {
  const _ServiceFormBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ServiceFormCubit, ServiceFormState>(
      listener: (context, state) {
        if (state is ServiceFormStateSaved) {
          Navigator.of(context).pop(state.service);
        }
      },
      builder: (context, state) {
        return switch (state) {
          ServiceFormStateInitial() => const Center(
              child: CircularProgressIndicator(),
            ),
          ServiceFormStateLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          ServiceFormStateError(message: final message) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $message', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<ServiceFormCubit>().save(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ServiceFormStateSaving() => const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Saving service...'),
                ],
              ),
            ),
          ServiceFormStateLoaded(
            categories: final categories,
            name: final name,
            price: final price,
            selectedCategoryId: final selectedCategoryId,
            fieldErrors: final fieldErrors,
          ) => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildNameField(context, name, fieldErrors['name']),
                  const SizedBox(height: 16),
                  _buildPriceField(context, price, fieldErrors['price']),
                  const SizedBox(height: 16),
                  _buildCategoryField(context, categories, selectedCategoryId, fieldErrors['category']),
                  const SizedBox(height: 24),
                  if (fieldErrors['general'] != null) ...[
                    Text(
                      fieldErrors['general']!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildSaveButton(context, state),
                ],
              ),
            ),
          ServiceFormStateSaved(service: final service) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'Service ${service.name} saved successfully!',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Price: ${CurrencyFormatter.format(service.price)}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
        };
      },
    );
  }

  Widget _buildNameField(BuildContext context, String name, String? error) {
    return TextFormField(
      initialValue: name,
      decoration: InputDecoration(
        labelText: 'Service Name',
        hintText: 'e.g., Haircut, Facial, Manicure',
        border: const OutlineInputBorder(),
        errorText: error,
        prefixIcon: const Icon(Icons.medical_services),
      ),
      onChanged: (value) => context.read<ServiceFormCubit>().updateName(value),
      textInputAction: TextInputAction.next,
    );
  }

  Widget _buildPriceField(BuildContext context, double price, String? error) {
    return TextFormField(
      initialValue: price == 0 ? '' : price.toString(),
      decoration: InputDecoration(
        labelText: 'Price',
        hintText: 'e.g., 500.00',
        border: const OutlineInputBorder(),
        errorText: error,
        prefixIcon: const Icon(Icons.currency_rupee),
        suffixText: '₹',
      ),
      keyboardType: TextInputType.number,
      onChanged: (value) => context.read<ServiceFormCubit>().updatePrice(value),
      textInputAction: TextInputAction.next,
    );
  }

  Widget _buildCategoryField(
    BuildContext context,
    List<ServiceCategory> categories,
    String selectedCategoryId,
    String? error,
  ) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Category',
        border: const OutlineInputBorder(),
        errorText: error,
        prefixIcon: const Icon(Icons.category),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedCategoryId.isEmpty ? null : selectedCategoryId,
          isExpanded: true,
          hint: const Text('Select a category'),
          items: [
            const DropdownMenuItem<String>(
              value: '',
              child: Text('Select a category'),
            ),
            ...categories.map((category) {
              return DropdownMenuItem<String>(
                value: category.id,
                child: Text(category.name),
              );
            }),
          ],
          onChanged: (value) {
            if (value != null && value.isNotEmpty) {
              context.read<ServiceFormCubit>().selectCategory(value);
            }
          },
        ),
      ),
    );
  }

  Widget _buildSaveButton(BuildContext context, ServiceFormStateLoaded state) {
    return ElevatedButton(
      onPressed: state.isValid ? () => context.read<ServiceFormCubit>().save() : null,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: Colors.blue,
      ),
      child: Text(
        state.isEditing ? 'Update Service' : 'Create Service',
        style: const TextStyle(fontSize: 16, color: Colors.white),
      ),
    );
  }
}