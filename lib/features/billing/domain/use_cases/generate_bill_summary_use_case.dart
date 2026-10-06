import '../../../../core/utils/result.dart';
import '../../../settings/domain/settings_repository.dart';
import '../bill.dart';

class GenerateBillSummaryUseCase {
  final SettingsRepository _settingsRepository;
  GenerateBillSummaryUseCase(this._settingsRepository);

  Future<Result<String>> call(Bill bill) async {
    try {
      final settingsResult = await _settingsRepository.getSettings();
      if (settingsResult is Failure) {
        return Failure((settingsResult as Failure).failure);
      }
      final settings = (settingsResult as Success).value;
      final currency = settings.currencySymbol;

      final buffer = StringBuffer();
      buffer.writeln('=== ${settings.parlourName} ===');
      buffer.writeln('Date: ${_formatDate(bill.visitDate)}');
      buffer.writeln('');
      buffer.writeln('Services:');
      for (final item in bill.lineItems) {
        buffer.writeln('  ${item.serviceName.padRight(30)} $currency${item.servicePrice.toStringAsFixed(2)}');
      }
      buffer.writeln('');
      buffer.writeln('Subtotal: $currency${bill.subtotal.toStringAsFixed(2)}');
      if (bill.discountAmount > 0) {
        final discountLabel = bill.discountType == DiscountType.percentage
            ? 'Discount (${bill.discountAmount.toStringAsFixed(0)}%)'
            : 'Discount';
        buffer.writeln('$discountLabel: -$currency${bill.discountAmount.toStringAsFixed(2)}');
      }
      buffer.writeln('Total: $currency${bill.total.toStringAsFixed(2)}');
      buffer.writeln('');
      buffer.writeln('Status: ${bill.status.name.toUpperCase()}');

      return Success(buffer.toString());
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}
