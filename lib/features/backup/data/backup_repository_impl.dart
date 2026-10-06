import 'dart:convert';

import '../../../../core/utils/result.dart';
import '../../../billing/data/bills_dao.dart';
import '../../../billing/domain/bill.dart';
import '../../../customers/data/customers_dao.dart';
import '../../../customers/domain/customer.dart';
import '../../../payments/data/payments_dao.dart';
import '../../../payments/domain/payment.dart';
import '../../../services/data/services_dao.dart';
import '../../../services/domain/service.dart';
import '../../../services/domain/service_category.dart';
import '../../../settings/domain/app_settings_entity.dart';
import '../../../settings/domain/settings_repository.dart';
import '../domain/backup_data.dart';
import '../domain/backup_repository.dart';
import '../domain/drive_service.dart';

const _kBackupFileName = 'parlour_backup.json';

class BackupRepositoryImpl implements BackupRepository {
  final CustomersDao _customersDao;
  final ServicesDao _servicesDao;
  final BillsDao _billsDao;
  final PaymentsDao _paymentsDao;
  final DriveService _driveService;
  final SettingsRepository _settingsRepository;

  BackupRepositoryImpl({
    required CustomersDao customersDao,
    required ServicesDao servicesDao,
    required BillsDao billsDao,
    required PaymentsDao paymentsDao,
    required DriveService driveService,
    required SettingsRepository settingsRepository,
  })  : _customersDao = customersDao,
        _servicesDao = servicesDao,
        _billsDao = billsDao,
        _paymentsDao = paymentsDao,
        _driveService = driveService,
        _settingsRepository = settingsRepository;

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  @override
  Future<Result<String>> exportAsJson() async {
    try {
      final data = await _collectAllData();
      final json = jsonEncode(data);
      return Success(json);
    } catch (e) {
      return Failure(BackupFailure(e.toString()));
    }
  }

  @override
  Future<Result<String>> exportAsCsv() async {
    try {
      final customers = await _customersDao.getAllCustomers();
      final bills = await _billsDao.getAllBills();

      final buffer = StringBuffer();

      // Customers section.
      buffer.writeln('=== CUSTOMERS ===');
      buffer.writeln('id,fullName,phoneNumber,notes,createdAt');
      for (final c in customers) {
        buffer.writeln(
          '${_csvEscape(c.id)},${_csvEscape(c.fullName)},${_csvEscape(c.phoneNumber)},${_csvEscape(c.notes ?? '')},${c.createdAt.toIso8601String()}',
        );
      }

      buffer.writeln('');

      // Bills section.
      buffer.writeln('=== BILLS ===');
      buffer.writeln('id,customerId,subtotal,discountAmount,discountType,total,status,visitDate');
      for (final b in bills) {
        buffer.writeln(
          '${_csvEscape(b.id)},${_csvEscape(b.customerId)},${b.subtotal},${b.discountAmount},${b.discountType?.name ?? ''},${b.total},${b.status.name},${b.visitDate.toIso8601String()}',
        );
      }

      return Success(buffer.toString());
    } catch (e) {
      return Failure(BackupFailure(e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Google Drive
  // ---------------------------------------------------------------------------

  @override
  Future<Result<void>> backupToGoogleDrive() async {
    try {
      await _driveService.signIn();
      final jsonResult = await exportAsJson();
      if (jsonResult is Failure) return Failure((jsonResult as Failure).failure);

      final jsonString = (jsonResult as Success<String>).value;
      final bytes = utf8.encode(jsonString);
      await _driveService.uploadFile(_kBackupFileName, bytes);
      return const Success(null);
    } catch (e) {
      return Failure(BackupFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> restoreFromGoogleDrive() async {
    try {
      await _driveService.signIn();
      final bytes = await _driveService.downloadFile(_kBackupFileName);
      if (bytes == null) {
        return const Failure(BackupFailure('No backup file found on Google Drive.'));
      }

      final jsonString = utf8.decode(bytes);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      await _applyBackupData(data);
      return const Success(null);
    } catch (e) {
      return Failure(BackupFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> restoreFromJson(String jsonString) async {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      await _applyBackupData(data);
      return const Success(null);
    } catch (e) {
      return Failure(BackupFailure(e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Conflict detection & resolution
  // ---------------------------------------------------------------------------

  @override
  Future<Result<BackupConflict?>> detectConflict() async {
    try {
      await _driveService.signIn();
      final remoteModified = await _driveService.getFileModifiedTime(_kBackupFileName);
      if (remoteModified == null) return const Success(null);

      final localData = await _collectAllData();
      final localUpdatedAt = DateTime.parse(localData['updatedAt'] as String);

      if (remoteModified.isAfter(localUpdatedAt)) {
        final remoteBytes = await _driveService.downloadFile(_kBackupFileName);
        if (remoteBytes == null) return const Success(null);

        final remoteJson = jsonDecode(utf8.decode(remoteBytes)) as Map<String, dynamic>;
        final remoteUpdatedAt = DateTime.parse(remoteJson['updatedAt'] as String);

        final conflict = BackupConflict(
          local: BackupData(updatedAt: localUpdatedAt, data: localData),
          remote: BackupData(updatedAt: remoteUpdatedAt, data: remoteJson),
        );
        return Success(conflict);
      }

      return const Success(null);
    } catch (e) {
      return Failure(BackupFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> resolveConflict(ConflictResolution resolution) async {
    try {
      switch (resolution) {
        case ConflictResolution.useLocal:
          return backupToGoogleDrive();
        case ConflictResolution.useRemote:
          return restoreFromGoogleDrive();
      }
    } catch (e) {
      return Failure(BackupFailure(e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _collectAllData() async {
    final customers = await _customersDao.getAllCustomers();
    final services = await _servicesDao.getAllServices();
    final categories = await _servicesDao.getAllCategories();
    final bills = await _billsDao.getAllBills();

    // Collect all payments for all bills.
    final allPayments = <Map<String, dynamic>>[];
    for (final bill in bills) {
      final payments = await _paymentsDao.getPaymentsForBill(bill.id);
      for (final p in payments) {
        allPayments.add({
          'id': p.id,
          'billId': p.billId,
          'amount': p.amount,
          'method': p.method.name,
          'paidAt': p.paidAt.toIso8601String(),
        });
      }
    }

    final settingsResult = await _settingsRepository.getSettings();
    AppSettingsEntity? settings;
    if (settingsResult is Success<AppSettingsEntity>) {
      settings = settingsResult.value;
    }
    final settingsMap = settings != null
        ? {
            'parlourName': settings.parlourName,
            'ownerName': settings.ownerName,
            'ownerPhone': settings.ownerPhone,
            'currencySymbol': settings.currencySymbol,
            'notificationsEnabled': settings.notificationsEnabled,
          }
        : <String, dynamic>{};

    return {
      'updatedAt': DateTime.now().toIso8601String(),
      'customers': customers
          .map((c) => {
                'id': c.id,
                'fullName': c.fullName,
                'phoneNumber': c.phoneNumber,
                'notes': c.notes,
                'photoPath': c.photoPath,
                'createdAt': c.createdAt.toIso8601String(),
                'updatedAt': c.updatedAt.toIso8601String(),
              })
          .toList(),
      'categories': categories
          .map((cat) => {'id': cat.id, 'name': cat.name})
          .toList(),
      'services': services
          .map((s) => {
                'id': s.id,
                'name': s.name,
                'price': s.price,
                'categoryId': s.categoryId,
                'isActive': s.isActive,
              })
          .toList(),
      'bills': bills
          .map((b) => {
                'id': b.id,
                'customerId': b.customerId,
                'appointmentId': b.appointmentId,
                'subtotal': b.subtotal,
                'discountAmount': b.discountAmount,
                'discountType': b.discountType?.name,
                'total': b.total,
                'status': b.status.name,
                'visitDate': b.visitDate.toIso8601String(),
                'lineItems': b.lineItems
                    .map((li) => {
                          'serviceId': li.serviceId,
                          'serviceName': li.serviceName,
                          'servicePrice': li.servicePrice,
                        })
                    .toList(),
              })
          .toList(),
      'payments': allPayments,
      'settings': settingsMap,
    };
  }

  Future<void> _applyBackupData(Map<String, dynamic> data) async {
    // Restore categories.
    final categoriesJson = data['categories'] as List<dynamic>? ?? [];
    for (final c in categoriesJson) {
      final map = c as Map<String, dynamic>;
      await _servicesDao.insertCategory(
        ServiceCategory(id: map['id'] as String, name: map['name'] as String),
      );
    }

    // Restore services.
    final servicesJson = data['services'] as List<dynamic>? ?? [];
    for (final s in servicesJson) {
      final map = s as Map<String, dynamic>;
      await _servicesDao.insertService(ParlourService(
        id: map['id'] as String,
        name: map['name'] as String,
        price: (map['price'] as num).toDouble(),
        categoryId: map['categoryId'] as String,
        isActive: map['isActive'] as bool,
      ));
    }

    // Restore customers.
    final customersJson = data['customers'] as List<dynamic>? ?? [];
    for (final c in customersJson) {
      final map = c as Map<String, dynamic>;
      await _customersDao.insertCustomer(Customer(
        id: map['id'] as String,
        fullName: map['fullName'] as String,
        phoneNumber: map['phoneNumber'] as String,
        notes: map['notes'] as String?,
        photoPath: map['photoPath'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      ));
    }

    // Restore bills.
    final billsJson = data['bills'] as List<dynamic>? ?? [];
    for (final b in billsJson) {
      final map = b as Map<String, dynamic>;
      final bill = _billFromMap(map);
      await _billsDao.insertBill(bill);
      await _billsDao.insertBillLineItems(bill.id, bill.lineItems);
    }

    // Restore payments.
    final paymentsJson = data['payments'] as List<dynamic>? ?? [];
    for (final p in paymentsJson) {
      final map = p as Map<String, dynamic>;
      await _paymentsDao.insertPayment(Payment(
        id: map['id'] as String,
        billId: map['billId'] as String,
        amount: (map['amount'] as num).toDouble(),
        method: PaymentMethod.values.firstWhere(
          (m) => m.name == map['method'],
          orElse: () => PaymentMethod.cash,
        ),
        paidAt: DateTime.parse(map['paidAt'] as String),
      ));
    }
  }

  Bill _billFromMap(Map<String, dynamic> map) {
    final lineItemsJson = map['lineItems'] as List<dynamic>? ?? [];
    final lineItems = lineItemsJson.map((li) {
      final liMap = li as Map<String, dynamic>;
      return BillLineItem(
        serviceId: liMap['serviceId'] as String,
        serviceName: liMap['serviceName'] as String,
        servicePrice: (liMap['servicePrice'] as num).toDouble(),
      );
    }).toList();

    return Bill(
      id: map['id'] as String,
      customerId: map['customerId'] as String,
      appointmentId: map['appointmentId'] as String?,
      subtotal: (map['subtotal'] as num).toDouble(),
      discountAmount: (map['discountAmount'] as num).toDouble(),
      discountType: _parseDiscountType(map['discountType'] as String?),
      total: (map['total'] as num).toDouble(),
      status: _parseBillStatus(map['status'] as String),
      visitDate: DateTime.parse(map['visitDate'] as String),
      lineItems: lineItems,
    );
  }

  BillStatus _parseBillStatus(String value) {
    return BillStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => BillStatus.draft,
    );
  }

  DiscountType? _parseDiscountType(String? value) {
    if (value == null) return null;
    return DiscountType.values.firstWhere(
      (d) => d.name == value,
      orElse: () => DiscountType.flat,
    );
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
