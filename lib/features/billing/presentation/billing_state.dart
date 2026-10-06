part of 'billing_cubit.dart';

/// A line item being built in the billing form (before saving).
class DraftLineItem {
  final String serviceId;
  final String serviceName;
  final double catalogPrice; // original price from catalog
  final double customPrice;  // editable price (starts equal to catalogPrice)

  const DraftLineItem({
    required this.serviceId,
    required this.serviceName,
    required this.catalogPrice,
    required this.customPrice,
  });

  DraftLineItem copyWith({double? customPrice}) {
    return DraftLineItem(
      serviceId: serviceId,
      serviceName: serviceName,
      catalogPrice: catalogPrice,
      customPrice: customPrice ?? this.customPrice,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DraftLineItem &&
          runtimeType == other.runtimeType &&
          serviceId == other.serviceId;

  @override
  int get hashCode => serviceId.hashCode;
}

sealed class BillingState {
  const BillingState();

  const factory BillingState.initial() = BillingStateInitial;
  const factory BillingState.loading() = BillingStateLoading;
  factory BillingState.ready({
    required List<ParlourService> availableServices,
    required List<ServiceCategory> categories,
    required List<DraftLineItem> lineItems,
    required double discountAmount,
    required DiscountType? discountType,
    String? selectedCategoryId,
  }) = BillingStateReady;
  const factory BillingState.saving() = BillingStateSaving;
  factory BillingState.saved({required Bill bill}) = BillingStateSaved;
  const factory BillingState.error(String message) = BillingStateError;
}

final class BillingStateInitial extends BillingState {
  const BillingStateInitial();
}

final class BillingStateLoading extends BillingState {
  const BillingStateLoading();
}

final class BillingStateReady extends BillingState {
  final List<ParlourService> availableServices;
  final List<ServiceCategory> categories;
  final List<DraftLineItem> lineItems;
  final double discountAmount;
  final DiscountType? discountType;
  final String? selectedCategoryId;

  const BillingStateReady({
    required this.availableServices,
    required this.lineItems,
    required this.discountAmount,
    required this.discountType,
    required this.categories,
    this.selectedCategoryId,
  });

  List<ParlourService> get filteredServices {
    if (selectedCategoryId == null) return availableServices;
    return availableServices
        .where((s) => s.categoryId == selectedCategoryId)
        .toList();
  }

  double get subtotal =>
      lineItems.fold(0.0, (sum, item) => sum + item.customPrice);

  double get total {
    if (discountType == DiscountType.flat) {
      return (subtotal - discountAmount).clamp(0.0, double.infinity);
    } else if (discountType == DiscountType.percentage) {
      return subtotal * (1 - discountAmount / 100);
    }
    return subtotal;
  }

  BillingStateReady copyWith({
    List<ParlourService>? availableServices,
    List<ServiceCategory>? categories,
    List<DraftLineItem>? lineItems,
    double? discountAmount,
    DiscountType? Function()? discountType,
    String? Function()? selectedCategoryId,
  }) {
    return BillingStateReady(
      availableServices: availableServices ?? this.availableServices,
      categories: categories ?? this.categories,
      lineItems: lineItems ?? this.lineItems,
      discountAmount: discountAmount ?? this.discountAmount,
      discountType: discountType != null ? discountType() : this.discountType,
      selectedCategoryId: selectedCategoryId != null
          ? selectedCategoryId()
          : this.selectedCategoryId,
    );
  }
}

final class BillingStateSaving extends BillingState {
  const BillingStateSaving();
}

final class BillingStateSaved extends BillingState {
  final Bill bill;
  const BillingStateSaved({required this.bill});
}

final class BillingStateError extends BillingState {
  final String message;
  const BillingStateError(this.message);
}
