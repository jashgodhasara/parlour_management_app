import '../bill.dart';

class CalculateBillTotalUseCase {
  const CalculateBillTotalUseCase();

  /// Calculates the bill total given a list of service prices and an optional discount.
  /// Returns a value clamped to >= 0.
  double call({
    required List<double> servicePrices,
    required double discountAmount,
    DiscountType? discountType,
  }) {
    final sum = servicePrices.fold<double>(0.0, (acc, price) => acc + price);

    double total;
    if (discountType == DiscountType.flat) {
      total = sum - discountAmount;
    } else if (discountType == DiscountType.percentage) {
      total = sum * (1 - discountAmount / 100);
    } else {
      total = sum;
    }

    return total.clamp(0.0, double.infinity);
  }
}
