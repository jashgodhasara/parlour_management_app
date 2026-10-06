import 'package:equatable/equatable.dart';

import '../domain/service.dart';
import '../domain/service_category.dart';

part of 'service_form_cubit.dart';

sealed class ServiceFormState extends Equatable {
  const ServiceFormState();

  @override
  List<Object?> get props => [];
}

class ServiceFormStateInitial extends ServiceFormState {
  const ServiceFormStateInitial();
}

class ServiceFormStateLoading extends ServiceFormState {
  const ServiceFormStateLoading();
}

class ServiceFormStateLoaded extends ServiceFormState {
  final ParlourService? service;
  final List<ServiceCategory> categories;
  final String name;
  final double price;
  final String selectedCategoryId;
  final Map<String, String> fieldErrors;

  const ServiceFormStateLoaded({
    this.service,
    required this.categories,
    required this.name,
    required this.price,
    required this.selectedCategoryId,
    this.fieldErrors = const {},
  });

  ServiceFormStateLoaded copyWith({
    ParlourService? service,
    List<ServiceCategory>? categories,
    String? name,
    double? price,
    String? selectedCategoryId,
    Map<String, String>? fieldErrors,
  }) {
    return ServiceFormStateLoaded(
      service: service ?? this.service,
      categories: categories ?? this.categories,
      name: name ?? this.name,
      price: price ?? this.price,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      fieldErrors: fieldErrors ?? this.fieldErrors,
    );
  }

  bool get isEditing => service != null;
  bool get isValid => name.trim().isNotEmpty && price >= 0 && selectedCategoryId.isNotEmpty;
  String? get nameError => fieldErrors['name'];
  String? get priceError => fieldErrors['price'];
  String? get categoryError => fieldErrors['category'];

  @override
  List<Object?> get props => [
        service,
        categories,
        name,
        price,
        selectedCategoryId,
        fieldErrors,
      ];
}

class ServiceFormStateSaving extends ServiceFormState {
  const ServiceFormStateSaving();
}

class ServiceFormStateSaved extends ServiceFormState {
  final ParlourService service;

  const ServiceFormStateSaved(this.service);

  @override
  List<Object?> get props => [service];
}

class ServiceFormStateError extends ServiceFormState {
  final String message;

  const ServiceFormStateError(this.message);

  @override
  List<Object?> get props => [message];
}