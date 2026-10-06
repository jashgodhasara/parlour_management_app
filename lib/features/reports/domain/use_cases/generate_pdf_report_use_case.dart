import '../../../../core/utils/result.dart';
import '../../../settings/domain/app_settings_entity.dart';
import '../../../settings/domain/settings_repository.dart';
import '../monthly_summary.dart';
import '../report_repository.dart';
import '../yearly_summary.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class GeneratePdfReportUseCase {
  final ReportRepository _reportRepository;
  final SettingsRepository _settingsRepository;
  GeneratePdfReportUseCase(this._reportRepository, this._settingsRepository);

  Future<Result<List<int>>> call(int year, int month) async {
    return monthly(year, month);
  }

  Future<Result<List<int>>> monthly(int year, int month) async {
    try {
      final summaryResult =
          await _reportRepository.getMonthlySummary(year, month);
      if (summaryResult is Failure<MonthlySummary>) {
        return Failure(summaryResult.failure);
      }
      final summary = (summaryResult as Success<MonthlySummary>).value;

      final settingsResult = await _settingsRepository.getSettings();
      if (settingsResult is Failure<AppSettingsEntity>) {
        return Failure(settingsResult.failure);
      }
      final settings = (settingsResult as Success<AppSettingsEntity>).value;

      final document = pw.Document();
      final monthLabel = DateFormat('MMMM yyyy').format(DateTime(year, month));
      final generatedAt =
          DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
      final categoryRows = summary.revenueByCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            _header(
              parlourName: settings.parlourName,
              title: 'Monthly Statement - $monthLabel',
              generatedAt: generatedAt,
            ),
            pw.Divider(height: 28),
            _summaryTable(
              visitCount: summary.visitCount,
              totalRevenue: summary.totalRevenue,
              totalDiscounts: summary.totalDiscounts,
              totalOutstanding: summary.totalOutstanding,
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'Service-wise statement',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (categoryRows.isEmpty)
              pw.Text('No service revenue found for this month.')
            else
              pw.TableHelper.fromTextArray(
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.all(8),
                data: [
                  ['Service', 'Revenue'],
                  ...categoryRows.map(
                    (entry) => [entry.key, _formatMoney(entry.value)],
                  ),
                ],
              ),
          ],
        ),
      );

      return Success(await document.save());
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  Future<Result<List<int>>> yearly(int year) async {
    try {
      final settingsResult = await _settingsRepository.getSettings();
      if (settingsResult is Failure<AppSettingsEntity>) {
        return Failure(settingsResult.failure);
      }
      final settings = (settingsResult as Success<AppSettingsEntity>).value;

      final yearlyResult = await _loadYearlySummary(year);
      if (yearlyResult is Failure<YearlySummary>) {
        return Failure(yearlyResult.failure);
      }
      final summary = (yearlyResult as Success<YearlySummary>).value;

      final document = pw.Document();
      final generatedAt =
          DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
      final categoryRows = summary.revenueByCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            _header(
              parlourName: settings.parlourName,
              title: 'Yearly Statement - $year',
              generatedAt: generatedAt,
            ),
            pw.Divider(height: 28),
            _summaryTable(
              visitCount: summary.visitCount,
              totalRevenue: summary.totalRevenue,
              totalDiscounts: summary.totalDiscounts,
              totalOutstanding: summary.totalOutstanding,
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'Month-wise statement',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(7),
              data: [
                ['Month', 'Visits', 'Revenue', 'Discounts', 'Outstanding'],
                ...summary.monthlySummaries.map(
                  (monthly) => [
                    DateFormat('MMM').format(DateTime(year, monthly.month)),
                    monthly.visitCount.toString(),
                    _formatMoney(monthly.totalRevenue),
                    _formatMoney(monthly.totalDiscounts),
                    _formatMoney(monthly.totalOutstanding),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'Service-wise statement',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (categoryRows.isEmpty)
              pw.Text('No service revenue found for this year.')
            else
              pw.TableHelper.fromTextArray(
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.all(8),
                data: [
                  ['Service', 'Revenue'],
                  ...categoryRows.map(
                    (entry) => [entry.key, _formatMoney(entry.value)],
                  ),
                ],
              ),
          ],
        ),
      );

      return Success(await document.save());
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  Future<Result<YearlySummary>> _loadYearlySummary(int year) async {
    final monthlySummaries = <MonthlySummary>[];
    final revenueByCategory = <String, double>{};
    var visitCount = 0;
    var totalRevenue = 0.0;
    var totalDiscounts = 0.0;
    var totalOutstanding = 0.0;

    for (var month = 1; month <= 12; month++) {
      final result = await _reportRepository.getMonthlySummary(year, month);
      if (result is Failure<MonthlySummary>) {
        return Failure(result.failure);
      }
      final summary = (result as Success<MonthlySummary>).value;
      monthlySummaries.add(summary);
      visitCount += summary.visitCount;
      totalRevenue += summary.totalRevenue;
      totalDiscounts += summary.totalDiscounts;
      totalOutstanding += summary.totalOutstanding;

      for (final entry in summary.revenueByCategory.entries) {
        revenueByCategory.update(
          entry.key,
          (existing) => existing + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }

    return Success(
      YearlySummary(
        year: year,
        visitCount: visitCount,
        totalRevenue: totalRevenue,
        totalDiscounts: totalDiscounts,
        totalOutstanding: totalOutstanding,
        revenueByCategory: revenueByCategory,
        monthlySummaries: monthlySummaries,
      ),
    );
  }

  pw.Widget _header({
    required String parlourName,
    required String title,
    required String generatedAt,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          parlourName,
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(title, style: const pw.TextStyle(fontSize: 16)),
        pw.Text(
          'Generated: $generatedAt',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    );
  }

  pw.Widget _summaryTable({
    required int visitCount,
    required double totalRevenue,
    required double totalDiscounts,
    required double totalOutstanding,
  }) {
    return pw.TableHelper.fromTextArray(
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.grey300,
      ),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.all(8),
      data: [
        ['Metric', 'Value'],
        ['Total visits', visitCount.toString()],
        ['Total revenue', _formatMoney(totalRevenue)],
        ['Total discounts', _formatMoney(totalDiscounts)],
        ['Total outstanding', _formatMoney(totalOutstanding)],
      ],
    );
  }

  String _formatMoney(double amount) {
    final formatter = NumberFormat('#,##,##0.00', 'en_IN');
    return 'Rs. ${formatter.format(amount)}';
  }
}
