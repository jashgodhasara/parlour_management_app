import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/currency_formatter.dart';
import 'service_catalog_cubit.dart';
import 'service_catalog_state.dart';

class ServiceCatalogScreen extends StatelessWidget {
  const ServiceCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ServiceCatalogCubit(
        serviceCatalogRepository: sl<ServiceCatalogRepository>(),
        setServiceActiveUseCase: sl<SetServiceActiveUseCase>(),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Service Catalog'),
        ),
        body: const _ServiceCatalogBody(),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push('/settings/services/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _ServiceCatalogBody extends StatelessWidget {
  const _ServiceCatalogBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServiceCatalogCubit, ServiceCatalogState>(
      builder: (context, state) {
        return switch (state) {
          ServiceCatalogStateInitial() => const Center(
              child: CircularProgressIndicator(),
            ),
          ServiceCatalogStateLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          ServiceCatalogStateError(message: final message) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: $message', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<ServiceCatalogCubit>().refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ServiceCatalogStateLoaded(
            categories: final categories,
            selectedCategoryId: final selectedCategoryId,
          ) => Column(
              children: [
                _buildCategoryFilter(categories, selectedCategoryId, context),
                Expanded(
                  child: _buildServiceList(context, state),
                ),
              ],
            ),
        };
      },
    );
  }

  Widget _buildCategoryFilter(
    List<ServiceCategory> categories,
    String? selectedCategoryId,
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildCategoryChip(
              category: null,
              label: 'All Services',
              isSelected: selectedCategoryId == null,
              onTap: () => context.read<ServiceCatalogCubit>().selectCategory(null),
            ),
            ...categories.map((category) => _buildCategoryChip(
                  category: category,
                  label: category.name,
                  isSelected: selectedCategoryId == category.id,
                  onTap: () => context.read<ServiceCatalogCubit>().selectCategory(category.id),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip({
    required ServiceCategory? category,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
        backgroundColor: isSelected ? Colors.blue[100] : Colors.grey[200],
        selectedColor: Colors.blue,
        labelStyle: TextStyle(
          color: isSelected ? Colors.blue[900] : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildServiceList(BuildContext context, ServiceCatalogStateLoaded state) {
    final services = state.filteredServices;

    if (services.isEmpty) {
      return const Center(
        child: Text(
          'No services found',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => context.read<ServiceCatalogCubit>().refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: services.length,
        itemBuilder: (context, index) {
          final service = services[index];
          final category = state.categories.firstWhere(
            (c) => c.id == service.categoryId,
            orElse: () => ServiceCategory(id: '', name: 'Unknown'),
          );
          return _ServiceTile(
            service: service,
            category: category,
            onToggleActive: () => context.read<ServiceCatalogCubit>().toggleServiceActive(service),
          );
        },
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final ParlourService service;
  final ServiceCategory category;
  final VoidCallback onToggleActive;

  const _ServiceTile({
    required this.service,
    required this.category,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: _buildServiceIcon(),
        title: Text(
          service.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: service.isActive ? null : TextDecoration.lineThrough,
            color: service.isActive ? Colors.black : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              category.name,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              CurrencyFormatter.format(service.price),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
        trailing: Switch(
          value: service.isActive,
          onChanged: (_) => onToggleActive(),
          activeColor: Colors.green,
        ),
        onTap: () => context.push('/settings/services/${service.id}/edit'),
      ),
    );
  }

  Widget _buildServiceIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: service.isActive ? Colors.blue[100] : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _getServiceIcon(category.name),
        color: service.isActive ? Colors.blue : Colors.grey,
        size: 24,
      ),
    );
  }

  IconData _getServiceIcon(String categoryName) {
    final lowerCategory = categoryName.toLowerCase();
    if (lowerCategory.contains('hair')) return Icons.cut;
    if (lowerCategory.contains('skin')) return Icons.spa;
    if (lowerCategory.contains('nail')) return Icons.brush;
    if (lowerCategory.contains('massage')) return Icons.self_improvement;
    if (lowerCategory.contains('facial')) return Icons.face;
    return Icons.medical_services;
  }
}