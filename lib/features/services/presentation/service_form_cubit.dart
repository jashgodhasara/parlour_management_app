import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/utils/result.dart';
import '../domain/service.dart';
import '../domain/service_catalog_repository.dart';
import '../domain/use_cases/create_service_use_case.dart';
import '../domain/use_cases/update_service_use_case.dart';

part 'service_form_state.dart';

class ServiceFormCubit extends Cubit<ServiceFormState> {
  final ServiceCatalogRepository _serviceCatalogRepository;
  final CreateServiceUseCase _createServiceUseCase;
  final UpdateServiceUseCase _updateServiceUseCase;
  final String? _serviceId;

  ServiceFormCubit({
    required ServiceCatalogRepository serviceCatalogRepository,
    required CreateServiceUseCase createServiceUseCase,
    required UpdateServiceUseCase updateServiceUseCase,
    String? serviceId,
  })  : _serviceCatalogRepository = serviceCatalogRepository,
        _createServiceUseCase = createServiceUseCase,
        _updateServiceUseCase = updateServiceUseCase,
        _serviceId = serviceId,
        super(const ServiceFormStateInitial()) {
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    emit(const ServiceFormStateLoading());

    try {
      final categoriesResult = await _serviceCatalogRepository.getCategories();

      if (categoriesResult is Failure) {
        emit(ServiceFormStateError(categoriesResult.failure.message));
        return;
      }

      final categories = (categoriesResult as Success<List<ServiceCategory>>).value;
      
      if (_serviceId != null) {
        // Load existing service for editing
        final servicesResult = await _serviceCatalogRepository.getServicesByCategory('');
        if (servicesResult is Success) {
          final services = servicesResult.value;
          final service = services.firstWhere(
            (s) => s.id == _serviceId,
            orElse: () => throw Exception('Service not found'),
          );
          
          emit(ServiceFormStateLoaded(
            service: service,
            categories: categories,
            name: service.name,
            price: service.price,
            selectedCategoryId: service.categoryId,
          ));
        } else {
          emit(ServiceFormStateError('Failed to load service'));
        }
      } else {
        // New service
        final defaultCategoryId = categories.isNotEmpty ? categories.first.id : '';
        emit(ServiceFormStateLoaded(
          service: null,
          categories: categories,
          name: '',
          price: 0.0,
          selectedCategoryId: defaultCategoryId,
        ));
      }
    } catch (e) {
      emit(ServiceFormStateError(e.toString()));
    }
  }

  void updateName(String name) {
    final currentState = state;
    if (currentState is ServiceFormStateLoaded) {
      final updatedErrors = Map<String, String>.from(currentState.fieldErrors);
      updatedErrors.remove('name');
      
      emit(currentState.copyWith(
        name: name,
        fieldErrors: updatedErrors,
      ));
    }
  }

  void updatePrice(String priceText) {
    final currentState = state;
    if (currentState is! ServiceFormStateLoaded) {
      return;
    }

    final price = double.tryParse(priceText) ?? 0.0;
    final updatedErrors = Map<String, String>.from(currentState.fieldErrors);
    updatedErrors.remove('price');
    
    emit(currentState.copyWith(
      price: price,
      fieldErrors: updatedErrors,
    ));
  }

  void selectCategory(String categoryId) {
    final currentState = state;
    if (currentState is ServiceFormStateLoaded) {
      final updatedErrors = Map<String, String>.from(currentState.fieldErrors);
      updatedErrors.remove('category');
      
      emit(currentState.copyWith(
        selectedCategoryId: categoryId,
        fieldErrors: updatedErrors,
      ));
    }
  }

  Future<void> save() async {
    final currentState = state;
    if (currentState is! ServiceFormStateLoaded) {
      return;
    }

    // Validate
    final errors = <String, String>{};
    if (currentState.name.trim().isEmpty) {
      errors['name'] = 'Service name is required';
    }
    if (currentState.price < 0) {
      errors['price'] = 'Price must be ₹0 or more';
    }
    if (currentState.selectedCategoryId.isEmpty) {
      errors['category'] = 'Please select a category';
    }

    if (errors.isNotEmpty) {
      emit(currentState.copyWith(fieldErrors: errors));
      return;
    }

    emit(const ServiceFormStateSaving());

    try {
      if (currentState.isEditing) {
        // Update existing service
        final updatedService = currentState.service!.copyWith(
          name: currentState.name.trim(),
          price: currentState.price,
          categoryId: currentState.selectedCategoryId,
        );
        
        final result = await _updateServiceUseCase(updatedService);
        
        if (result is Failure) {
          final failure = result.failure;
          if (failure is InvalidServiceFailure) {
            emit(currentState.copyWith(fieldErrors: {'general': failure.message}));
          } else {
            emit(ServiceFormStateError(failure.message));
          }
          return;
        }
        
        final savedService = (result as Success<ParlourService>).value;
        emit(ServiceFormStateSaved(savedService));
      } else {
        // Create new service
        final result = await _createServiceUseCase(
          name: currentState.name.trim(),
          price: currentState.price,
          categoryId: currentState.selectedCategoryId,
        );
        
        if (result is Failure) {
          final failure = result.failure;
          if (failure is InvalidServiceFailure) {
            emit(currentState.copyWith(fieldErrors: {'general': failure.message}));
          } else {
            emit(ServiceFormStateError(failure.message));
          }
          return;
        }
        
        final savedService = (result as Success<ParlourService>).value;
        emit(ServiceFormStateSaved(savedService));
      }
    } catch (e) {
      emit(ServiceFormStateError(e.toString()));
    }
  }
}