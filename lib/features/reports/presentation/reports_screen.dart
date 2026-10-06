import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/injection.dart';
import '../../../core/utils/result.dart';
import '../domain/monthly_summary.dart';
import '../domain/use_cases/generate_pdf_report_use_case.dart';
import '../domain/use_cases/generate_xlsx_statement_use_case.dart';
import '../domain/use_cases/get_monthly_summary_use_case.dart';
import '../domain/use_cases/get_yearly_summary_use_case.dart';
import '../domain/yearly_summary.dart';

enum _StatementPeriod { monthly, yearly }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final GetMonthlySummaryUseCase _getMonthlySummaryUseCase;
  late final GetYearlySummaryUseCase _getYearlySummaryUseCase;
  late final GeneratePdfReportUseCase _generatePdfReportUseCase;
  late final GenerateXlsxStatementUseCase _generateXlsxStatementUseCase;
  late Future<Result<Object>> _statementFuture;
  late DateTime _selectedMonth;
  late int _selectedYear;
  var _period = _StatementPeriod.monthly;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _selectedYear = now.year;
    _getMonthlySummaryUseCase = sl<GetMonthlySummaryUseCase>();
    _getYearlySummaryUseCase = sl<GetYearlySummaryUseCase>();
    _generatePdfReportUseCase = sl<GeneratePdfReportUseCase>();
    _generateXlsxStatementUseCase = sl<GenerateXlsxStatementUseCase>();
    _statementFuture = _loadStatement();
  }

  Future<Result<Object>> _loadStatement() async {
    if (_period == _StatementPeriod.monthly) {
      final result = await _getMonthlySummaryUseCase(
        _selectedMonth.year,
        _selectedMonth.month,
      );
      if (result is Failure<MonthlySummary>) return Failure(result.failure);
      return Success<Object>((result as Success<MonthlySummary>).value);
    }

    final result = await _getYearlySummaryUseCase(_selectedYear);
    if (result is Failure<YearlySummary>) return Failure(result.failure);
    return Success<Object>((result as Success<YearlySummary>).value);
  }

  void _setPeriod(_StatementPeriod period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _statementFuture = _loadStatement();
    });
  }

  void _changePeriod(int delta) {
    setState(() {
      if (_period == _StatementPeriod.monthly) {
        _selectedMonth = DateTime(
          _selectedMonth.year,
          _selectedMonth.month + delta,
        );
        _selectedYear = _selectedMonth.year;
      } else {
        _selectedYear += delta;
        _selectedMonth = DateTime(_selectedYear, _selectedMonth.month);
      }
      _statementFuture = _loadStatement();
    });
  }

  Future<void> _sharePdf() async {
    if (_isSharing) return;

    setState(() => _isSharing = true);
    try {
      final Result<List<int>> result;
      final String fileName;
      final String text;

      if (_period == _StatementPeriod.monthly) {
        result = await _generatePdfReportUseCase.monthly(
          _selectedMonth.year,
          _selectedMonth.month,
        );
        final monthLabel = DateFormat('yyyy_MM').format(_selectedMonth);
        fileName = 'monthly_statement_$monthLabel.pdf';
        text = 'Monthly statement for ${_monthLabel(_selectedMonth)}';
      } else {
        result = await _generatePdfReportUseCase.yearly(_selectedYear);
        fileName = 'yearly_statement_$_selectedYear.pdf';
        text = 'Yearly statement for $_selectedYear';
      }

      if (!mounted) return;

      if (result is Failure<List<int>>) {
        _showMessage(result.failure.message);
        return;
      }

      final bytes = (result as Success<List<int>>).value;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: 'application/pdf',
              name: fileName,
            ),
          ],
          fileNameOverrides: [fileName],
          subject: 'Statement',
          title: 'Share statement',
          text: text,
        ),
      );
    } catch (e) {
      if (mounted) _showMessage('PDF share failed: $e');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _shareXlsx() async {
    if (_isSharing) return;

    setState(() => _isSharing = true);
    try {
      final Result<List<int>> result;
      final String fileName;
      final String text;

      if (_period == _StatementPeriod.monthly) {
        result = await _generateXlsxStatementUseCase.monthly(
          _selectedMonth.year,
          _selectedMonth.month,
        );
        final monthLabel = DateFormat('yyyy_MM').format(_selectedMonth);
        fileName = 'monthly_statement_$monthLabel.xlsx';
        text = 'Monthly Excel statement for ${_monthLabel(_selectedMonth)}';
      } else {
        result = await _generateXlsxStatementUseCase.yearly(_selectedYear);
        fileName = 'yearly_statement_$_selectedYear.xlsx';
        text = 'Yearly Excel statement for $_selectedYear';
      }

      if (!mounted) return;

      if (result is Failure<List<int>>) {
        _showMessage(result.failure.message);
        return;
      }

      final bytes = (result as Success<List<int>>).value;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: fileName,
            ),
          ],
          fileNameOverrides: [fileName],
          subject: 'Excel statement',
          title: 'Share Excel statement',
          text: text,
        ),
      );
    } catch (e) {
      if (mounted) _showMessage('Excel share failed: $e');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statements'),
        actions: [
          IconButton(
            tooltip: 'Share PDF',
            onPressed: _isSharing ? null : _sharePdf,
            icon: _isSharing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
          ),
          IconButton(
            tooltip: 'Share Excel',
            onPressed: _isSharing ? null : _shareXlsx,
            icon: const Icon(Icons.table_chart),
          ),
        ],
      ),
      body: FutureBuilder<Result<Object>>(
        future: _statementFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final result = snapshot.data;
          if (result is Failure<Object>) {
            return Center(child: Text(result.failure.message));
          }

          if (result is! Success<Object>) {
            return const Center(child: Text('No statement data found.'));
          }

          return _StatementContent(
            period: _period,
            statement: result.value,
            selectedMonth: _selectedMonth,
            selectedYear: _selectedYear,
            isSharing: _isSharing,
            onPeriodChanged: _setPeriod,
            onPrevious: () => _changePeriod(-1),
            onNext: () => _changePeriod(1),
            onSharePdf: _sharePdf,
            onShareXlsx: _shareXlsx,
          );
        },
      ),
    );
  }
}

class _StatementContent extends StatelessWidget {
  final _StatementPeriod period;
  final Object statement;
  final DateTime selectedMonth;
  final int selectedYear;
  final bool isSharing;
  final ValueChanged<_StatementPeriod> onPeriodChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSharePdf;
  final VoidCallback onShareXlsx;

  const _StatementContent({
    required this.period,
    required this.statement,
    required this.selectedMonth,
    required this.selectedYear,
    required this.isSharing,
    required this.onPeriodChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onSharePdf,
    required this.onShareXlsx,
  });

  @override
  Widget build(BuildContext context) {
    final totals = _StatementTotals.from(statement);
    final categoryRows = totals.revenueByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: SegmentedButton<_StatementPeriod>(
            segments: const [
              ButtonSegment(
                value: _StatementPeriod.monthly,
                icon: Icon(Icons.calendar_month),
                label: Text('Monthly'),
              ),
              ButtonSegment(
                value: _StatementPeriod.yearly,
                icon: Icon(Icons.calendar_today),
                label: Text('Yearly'),
              ),
            ],
            selected: {period},
            onSelectionChanged: (selection) {
              onPeriodChanged(selection.first);
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: Text(
                  period == _StatementPeriod.monthly
                      ? _monthLabel(selectedMonth)
                      : selectedYear.toString(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: isSharing ? null : onSharePdf,
          icon: isSharing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.share),
          label: Text(
            period == _StatementPeriod.monthly
                ? 'Share Monthly PDF'
                : 'Share Yearly PDF',
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: isSharing ? null : onShareXlsx,
          icon: const Icon(Icons.table_chart),
          label: Text(
            period == _StatementPeriod.monthly
                ? 'Share Monthly Excel'
                : 'Share Yearly Excel',
          ),
        ),
        const SizedBox(height: 16),
        _SummaryGrid(totals: totals),
        if (statement is YearlySummary) ...[
          const SizedBox(height: 20),
          Text(
            'Month-wise statement',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...((statement as YearlySummary).monthlySummaries.map(
                (monthly) => Card(
                  child: ListTile(
                    title: Text(
                      DateFormat('MMMM').format(
                        DateTime(
                            (statement as YearlySummary).year, monthly.month),
                      ),
                    ),
                    subtitle: Text('${monthly.visitCount} visits'),
                    trailing: Text(_formatMoney(monthly.totalRevenue)),
                  ),
                ),
              )),
        ],
        const SizedBox(height: 20),
        Text(
          'Service-wise statement',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (categoryRows.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                period == _StatementPeriod.monthly
                    ? 'No service revenue found for this month.'
                    : 'No service revenue found for this year.',
              ),
            ),
          )
        else
          ...categoryRows.map(
            (entry) => Card(
              child: ListTile(
                title: Text(entry.key),
                trailing: Text(_formatMoney(entry.value)),
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final _StatementTotals totals;

  const _SummaryGrid({required this.totals});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width > 640 ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _SummaryCard(
          label: 'Visits',
          value: totals.visitCount.toString(),
          icon: Icons.people_alt,
        ),
        _SummaryCard(
          label: 'Revenue',
          value: _formatMoney(totals.totalRevenue),
          icon: Icons.payments,
        ),
        _SummaryCard(
          label: 'Discounts',
          value: _formatMoney(totals.totalDiscounts),
          icon: Icons.local_offer,
        ),
        _SummaryCard(
          label: 'Outstanding',
          value: _formatMoney(totals.totalOutstanding),
          icon: Icons.account_balance_wallet,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatementTotals {
  final int visitCount;
  final double totalRevenue;
  final double totalDiscounts;
  final double totalOutstanding;
  final Map<String, double> revenueByCategory;

  const _StatementTotals({
    required this.visitCount,
    required this.totalRevenue,
    required this.totalDiscounts,
    required this.totalOutstanding,
    required this.revenueByCategory,
  });

  factory _StatementTotals.from(Object statement) {
    if (statement is MonthlySummary) {
      return _StatementTotals(
        visitCount: statement.visitCount,
        totalRevenue: statement.totalRevenue,
        totalDiscounts: statement.totalDiscounts,
        totalOutstanding: statement.totalOutstanding,
        revenueByCategory: statement.revenueByCategory,
      );
    }

    final yearly = statement as YearlySummary;
    return _StatementTotals(
      visitCount: yearly.visitCount,
      totalRevenue: yearly.totalRevenue,
      totalDiscounts: yearly.totalDiscounts,
      totalOutstanding: yearly.totalOutstanding,
      revenueByCategory: yearly.revenueByCategory,
    );
  }
}

String _monthLabel(DateTime date) {
  return DateFormat('MMMM yyyy').format(date);
}

String _formatMoney(double amount) {
  final formatter = NumberFormat('#,##,##0.00', 'en_IN');
  return 'Rs. ${formatter.format(amount)}';
}
