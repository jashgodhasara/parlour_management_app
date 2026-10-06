import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/utils/result.dart';
import '../../services/domain/service.dart';
import '../../services/domain/service_catalog_repository.dart';
import '../../services/domain/service_category.dart';
import '../domain/bill.dart';
import '../domain/billing_repository.dart';
import '../domain/use_cases/create_bill_use_case.dart';
import '../domain/use_cases/finalise_bill_use_case.dart';

part 'billing_state.dart';

class BillingCubit extends Cubit<BillingState> {
  final ServiceCatalogRepository _serviceCatalogRepository;
  final CreateBillUseCase _createBillUseCase;
  final FinaliseBillUseCase _finaliseBillUseCase;
  final String? customerId;

  BillingCubit({
    required ServiceCatalogRepository serviceCatalogRepository,
    required CreateBillUseCase createBillUseCase,
    required FinaliseBillUseCase finaliseBillUseCase,
    this.customerId,
  })  : _serviceCatalogRepository = serviceCatalogRepository,
        _createBillUseCase = createBillUseCase,
        _finaliseBillUseCase = finaliseBillUseCase,
        super(const BillingState.initial()) {
    _loadServices();
  }

  Future<void> _loadServices() async {
    emit(const BillingState.loading());
    try {
      final servicesResult = await _serviceCatalogRepository.getActiveServices();
      final categoriesResult = await _serviceCatalogRepository.getCategories();

      if (servicesResult is Failure) {
        emit(BillingState.error(
            (servicesResult as Failure).failure.message));
        return;
      }
      if (categoriesResult is Failure) {
        emit(BillingState.error(
            (categoriesResult as Failure).failure.message));
        return;
      }

      final services = (servicesResult as Success<List<ParlourService>>).value;
      final categories =
          (categoriesResult as Success<List<ServiceCategory>>).value;

      emit(BillingState.ready(
        availableServices: services,
        categories: categories,
        lineItems: const [],
        discountAmount: 0,
        discountType: null,
      ));
    } catch (e) {
      emit(BillingState.error(e.toString()));
    }
  }

  void selectCategory(String? categoryId) {
    final current = state;
    if (current is! BillingStateReady) return;
    emit(current.copyWith(
        selectedCategoryId: () => categoryId));
  }

  /// Add a service to the bill. If already added, does nothing.
  void addService(ParlourService service) {
    final current = state;
    if (current is! BillingStateReady) return;
    if (current.lineItems.any((item) => item.serviceId == service.id)) return;

    final newItem = DraftLineItem(
      serviceId: service.id,
      serviceName: service.name,
      catalogPrice: service.price,
      customPrice: service.price,
    );
    emit(current.copyWith(lineItems: [...current.lineItems, newItem]));
  }

  /// Remove a service from the bill.
  void removeService(String serviceId) {
    final current = state;
    if (current is! BillingStateReady) return;
    emit(current.copyWith(
      lineItems:
          current.lineItems.where((i) => i.serviceId != serviceId).toList(),
    ));
  }

  /// Update the custom price for a specific line item.
  void updateLineItemPrice(String serviceId, double newPrice) {
    final current = state;
    if (current is! BillingStateReady) return;
    final updated = current.lineItems.map((item) {
      if (item.serviceId == serviceId) {
        return item.copyWith(customPrice: newPrice < 0 ? 0 : newPrice);
      }
      return item;
    }).toList();
    emit(current.copyWith(lineItems: updated));
  }

  void updateDiscount(double amount, DiscountType? type) {
    final current = state;
    if (current is! BillingStateReady) return;
    emit(current.copyWith(
      discountAmount: amount,
      discountType: () => type,
    ));
  }

  Future<void> saveBill() async {
    final current = state;
    if (current is! BillingStateReady) return;
    if (current.lineItems.isEmpty) return;
    if (customerId == null) return;

    emit(const BillingState.saving());

    final result = await _createBillUseCase(
      customerId: customerId!,
      serviceIds: current.lineItems.map((i) => i.serviceId).toList(),
      subtotal: current.subtotal,
      discountAmount: current.discountAmount,
      discountType: current.discountType,
      total: current.total,
    );

    switch (result) {
      case Success(value: final bill):
        // Finalise immediately so it's ready for payment.
        await _finaliseBillUseCase(bill.id);
        emit(BillingStateSaved(bill: bill));
      case Failure(failure: final failure):
        emit(BillingState.error(failure.message));
    }
  }
}
