import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/utils/result.dart';
import '../domain/service.dart';
import '../domain/service_catalog_repository.dart';
import '../domain/use_cases/set_service_active_use_case.dart';

part 'service_catalog_state.dart';

class ServiceCatalogCubit extends Cubit<ServiceCatalogState> {
  final ServiceCatalogRepository _serviceCatalogRepository;
  final SetServiceActiveUseCase _setServiceActiveUseCase;
  String? _selectedCategoryId;

  ServiceCatalogCubit({
    required ServiceCatalogRepository serviceCatalogRepository,
    required SetServiceActiveUseCase setServiceActiveUseCase,
  })  : _serviceCatalogRepository = serviceCatalogRepository,
        _setServiceActiveUseCase = setServiceActiveUseCase,
        super(const ServiceCatalogState.initial()) {
    loadServices();
  }

  Future<void> loadServices() async {
    emit(const ServiceCatalogState.loading());

    try {
      final servicesResult = await _serviceCatalogRepository.getActiveServices();
      final categoriesResult = await _serviceCatalogRepository.getCategories();

      if (servicesResult is Failure) {
        emit(ServiceCatalogState.error(servicesResult.failure.message));
        return;
      }

      if (categoriesResult is Failure) {
        emit(ServiceCatalogState.error(categoriesResult.failure.message));
        return;
      }

      final services = (servicesResult as Success<List<ParlourService>>).value;
      final categories = (categoriesResult as Success<List<ServiceCategory>>).value;

      // Group services by category
      final servicesByCategory = <String, List<ParlourService>>{};
      for (final service in services) {
        servicesByCategory.putIfAbsent(service.categoryId, () => []).add(service);
      }

      // Sort services alphabetically within each category
      for (final categoryServices in servicesByCategory.values) {
        categoryServices.sort((a, b) => a.name.compareTo(b.name));
      }

      emit(ServiceCatalogState.loaded(
        services: services,
        categories: categories,
        servicesByCategory: servicesByCategory,
        selectedCategoryId: _selectedCategoryId,
      ));
    } catch (e) {
      emit(ServiceCatalogState.error(e.toString()));
    }
  }

  void selectCategory(String? categoryId) {
    _selectedCategoryId = categoryId;
    final currentState = state;
    if (currentState is ServiceCatalogStateLoaded) {
      emit(currentState.copyWith(selectedCategoryId: categoryId));
    }
  }

  Future<void> toggleServiceActive(ParlourService service) async {
    final currentState = state;
    if (currentState is! ServiceCatalogStateLoaded) {
      return;
    }

    // Optimistically update UI
    final updatedService = service.copyWith(isActive: !service.isActive);
    final updatedServices = currentState.services.map((s) {
      return s.id == service.id ? updatedService : s;
    }).toList();

    // Update services by category
    final updatedServicesByCategory = Map<String, List<ParlourService>>.from(currentState.servicesByCategory);
    for (final entry in updatedServicesByCategory.entries) {
      final index = entry.value.indexWhere((s) => s.id == service.id);
      if (index != -1) {
        entry.value[index] = updatedService;
      }
    }

    emit(currentState.copyWith(
      services: updatedServices,
      servicesByCategory: updatedServicesByCategory,
    ));

    // Call use case
    final result = await _setServiceActiveUseCase(
      serviceId: service.id,
      isActive: !service.isActive,
    );

    if (result is Failure) {
      // Revert on error
      emit(currentState);
      // In a real app, you might want to show an error message
    }
  }

  Future<void> refresh() async {
    await loadServices();
  }
}