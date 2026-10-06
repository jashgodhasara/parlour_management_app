import 'package:equatable/equatable.dart';

import '../domain/service.dart';
import '../domain/service_category.dart';

part of 'service_catalog_cubit.dart';

sealed class ServiceCatalogState extends Equatable {
  const ServiceCatalogState();

  @override
  List<Object?> get props => [];
}

class ServiceCatalogStateInitial extends ServiceCatalogState {
  const ServiceCatalogStateInitial();
}

class ServiceCatalogStateLoading extends ServiceCatalogState {
  const ServiceCatalogStateLoading();
}

class ServiceCatalogStateLoaded extends ServiceCatalogState {
  final List<ParlourService> services;
  final List<ServiceCategory> categories;
  final Map<String, List<ParlourService>> servicesByCategory;
  final String? selectedCategoryId;

  const ServiceCatalogStateLoaded({
    required this.services,
    required this.categories,
    required this.servicesByCategory,
    this.selectedCategoryId,
  });

  ServiceCatalogStateLoaded copyWith({
    List<ParlourService>? services,
    List<ServiceCategory>? categories,
    Map<String, List<ParlourService>>? servicesByCategory,
    String? selectedCategoryId,
  }) {
    return ServiceCatalogStateLoaded(
      services: services ?? this.services,
      categories: categories ?? this.categories,
      servicesByCategory: servicesByCategory ?? this.servicesByCategory,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
    );
  }

  List<ParlourService> get filteredServices {
    if (selectedCategoryId == null) {
      return services;
    }
    return servicesByCategory[selectedCategoryId] ?? [];
  }

  @override
  List<Object?> get props => [
        services,
        categories,
        servicesByCategory,
        selectedCategoryId,
      ];
}

class ServiceCatalogStateError extends ServiceCatalogState {
  final String message;

  const ServiceCatalogStateError(this.message);

  @override
  List<Object?> get props => [message];
}