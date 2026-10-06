import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/result.dart';
import '../report_repository.dart';
import '../statement_transaction.dart';

enum StatementPeriod { monthly, yearly }

class GenerateXlsxStatementUseCase {
  final ReportRepository _repository;

  GenerateXlsxStatementUseCase(this._repository);

  Future<Result<List<int>>> monthly(int year, int month) {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final label = DateFormat('MMMM yyyy').format(start);
    return _generate(
        start: start, end: end, title: 'Monthly Statement', label: label);
  }

  Future<Result<List<int>>> yearly(int year) {
    final start = DateTime(year);
    final end = DateTime(year + 1);
    return _generate(
      start: start,
      end: end,
      title: 'Yearly Statement',
      label: year.toString(),
    );
  }

  Future<Result<List<int>>> _generate({
    required DateTime start,
    required DateTime end,
    required String title,
    required String label,
  }) async {
    try {
      final transactionsResult =
          await _repository.getTransactionsBetween(start, end);
      if (transactionsResult is Failure<List<StatementTransaction>>) {
        return Failure(transactionsResult.failure);
      }

      final transactions =
          (transactionsResult as Success<List<StatementTransaction>>).value;
      final excel = Excel.createExcel();
      const sheetName = 'Statement';
      excel.rename('Sheet1', sheetName);
      final sheet = excel[sheetName];

      _setWidths(sheet);
      _writeTitle(sheet, title, label);
      _writeSummary(sheet, transactions);
      _writeTransactions(sheet, transactions);

      final bytes = excel.encode();
      if (bytes == null) {
        return const Failure(DatabaseFailure('Could not generate Excel file.'));
      }
      return Success(bytes);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  void _writeTitle(Sheet sheet, String title, String label) {
    final titleStyle = CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.blueGrey,
      horizontalAlign: HorizontalAlign.Center,
    );
    final subtitleStyle = CellStyle(
      bold: true,
      fontSize: 12,
      backgroundColorHex: ExcelColor.grey,
      horizontalAlign: HorizontalAlign.Center,
    );

    sheet.merge(
      CellIndex.indexByString('A1'),
      CellIndex.indexByString('I1'),
      customValue: TextCellValue(title),
    );
    sheet.merge(
      CellIndex.indexByString('A2'),
      CellIndex.indexByString('I2'),
      customValue: TextCellValue(label),
    );
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = titleStyle;
    sheet.cell(CellIndex.indexByString('A2')).cellStyle = subtitleStyle;
  }

  void _writeSummary(Sheet sheet, List<StatementTransaction> transactions) {
    final totalBill = transactions.fold<double>(
      0,
      (total, transaction) => total + transaction.billAmount,
    );
    final totalPaid = transactions.fold<double>(
      0,
      (total, transaction) => total + transaction.paidAmount,
    );
    final totalOutstanding = transactions.fold<double>(
      0,
      (total, transaction) => total + transaction.outstandingAmount,
    );

    final headerStyle = _headerStyle();
    final moneyStyle = _moneyStyle();

    final rows = [
      ['Total Bills', transactions.length],
      ['Bill Amount', totalBill],
      ['Paid Amount', totalPaid],
      ['Outstanding', totalOutstanding],
    ];

    sheet.updateCell(
      'A4'.cellIndex,
      TextCellValue('Summary'),
      cellStyle: headerStyle,
    );

    for (var i = 0; i < rows.length; i++) {
      final row = 4 + i;
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        TextCellValue(rows[i][0] as String),
      );
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
        _cell(rows[i][1]),
        cellStyle: i == 0 ? null : moneyStyle,
      );
    }
  }

  void _writeTransactions(
    Sheet sheet,
    List<StatementTransaction> transactions,
  ) {
    final headerStyle = _headerStyle();
    final moneyStyle = _moneyStyle();
    final dateStyle = CellStyle(numberFormat: NumFormat.standard_14);
    final headers = [
      'Date',
      'Bill No',
      'Customer',
      'Phone',
      'Services',
      'Bill Amount',
      'Paid',
      'Outstanding',
      'Payment Mode',
    ];

    for (var i = 0; i < headers.length; i++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 10),
        TextCellValue(headers[i]),
        cellStyle: headerStyle,
      );
    }

    for (var i = 0; i < transactions.length; i++) {
      final row = 11 + i;
      final transaction = transactions[i];
      final cells = [
        DateCellValue(
          year: transaction.date.year,
          month: transaction.date.month,
          day: transaction.date.day,
        ),
        TextCellValue(transaction.billId),
        TextCellValue(transaction.customerName),
        TextCellValue(transaction.customerPhone),
        TextCellValue(transaction.services),
        DoubleCellValue(transaction.billAmount),
        DoubleCellValue(transaction.paidAmount),
        DoubleCellValue(transaction.outstandingAmount),
        TextCellValue(transaction.paymentMethods),
      ];

      for (var column = 0; column < cells.length; column++) {
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
          cells[column],
          cellStyle: column == 0
              ? dateStyle
              : column >= 5 && column <= 7
                  ? moneyStyle
                  : null,
        );
      }
    }
  }

  void _setWidths(Sheet sheet) {
    const widths = [14.0, 28.0, 24.0, 16.0, 34.0, 14.0, 14.0, 14.0, 16.0];
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }

  CellStyle _headerStyle() {
    return CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.blueGrey,
    );
  }

  CellStyle _moneyStyle() {
    return CellStyle(numberFormat: NumFormat.defaultFloat);
  }

  CellValue _cell(Object? value) {
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    return TextCellValue(value?.toString() ?? '');
  }
}

extension on String {
  CellIndex get cellIndex => CellIndex.indexByString(this);
}
