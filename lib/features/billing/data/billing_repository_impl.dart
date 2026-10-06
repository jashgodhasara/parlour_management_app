import 'package:uuid/uuid.dart';

import '../../../../core/utils/result.dart';
import '../../services/data/services_dao.dart';
import '../domain/bill.dart';
import '../domain/billing_repository.dart';
import 'bills_dao.dart';

class BillingRepositoryImpl implements BillingRepository {
  final BillsDao _billsDao;
  final ServicesDao _servicesDao;
  final _uuid = const Uuid();

  BillingRepositoryImpl(this._billsDao, this._servicesDao);

  @override
  Future<Result<Bill>> createBill({
    required String customerId,
    required List<String> serviceIds,
    required double subtotal,
    required double discountAmount,
    DiscountType? discountType,
    required double total,
    String? appointmentId,
  }) async {
    try {
      // Snapshot service names/prices into line items.
      final lineItems = <BillLineItem>[];
      for (final id in serviceIds) {
        final service = await _servicesDao.findById(id);
        if (service != null) {
          lineItems.add(BillLineItem(
            serviceId: service.id,
            serviceName: service.name,
            servicePrice: service.price,
          ));
        }
      }

      final bill = Bill(
        id: _uuid.v4(),
        customerId: customerId,
        appointmentId: appointmentId,
        subtotal: subtotal,
        discountAmount: discountAmount,
        discountType: discountType,
        total: total,
        status: BillStatus.draft,
        visitDate: DateTime.now(),
        lineItems: lineItems,
      );

      await _billsDao.insertBill(bill);
      await _billsDao.insertBillLineItems(bill.id, lineItems);
      return Success(bill);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<Bill>> finaliseBill(String billId) async {
    try {
      await _billsDao.updateBillStatus(billId, BillStatus.finalised);
      final bill = await _billsDao.getBillById(billId);
      if (bill == null) return const Failure(NotFoundFailure());
      return Success(bill);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<Bill>> markAsPaid(String billId) async {
    try {
      await _billsDao.updateBillStatus(billId, BillStatus.paid);
      final bill = await _billsDao.getBillById(billId);
      if (bill == null) return const Failure(NotFoundFailure());
      return Success(bill);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteBill(String id) async {
    try {
      final deleted = await _billsDao.deleteBill(id);
      if (!deleted) {
        return const Failure(NotFoundFailure('Bill not found.'));
      }

      return const Success(null);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<Bill?>> getBillById(String id) async {
    try {
      final bill = await _billsDao.getBillById(id);
      return Success(bill);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<Bill>>> getBillsForCustomer(String customerId) async {
    try {
      final bills = await _billsDao.getBillsForCustomer(customerId);
      return Success(bills);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<Bill>>> getVisitHistory(String customerId) =>
      getBillsForCustomer(customerId);

  @override
  Future<Result<Bill>> updateLineItemPrice({
    required String billId,
    required String serviceId,
    required double newPrice,
  }) async {
    try {
      final bill = await _billsDao.updateLineItemPrice(
        billId: billId,
        serviceId: serviceId,
        newPrice: newPrice,
      );
      if (bill == null) return const Failure(NotFoundFailure());
      return Success(bill);
    } catch (e) {
      return Failure(DatabaseFailure(e.toString()));
    }
  }
}
