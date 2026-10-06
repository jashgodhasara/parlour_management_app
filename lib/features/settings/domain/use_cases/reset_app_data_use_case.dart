import '../../../appointments/data/appointments_dao.dart';
import '../../../billing/data/bills_dao.dart';
import '../../../customers/data/customers_dao.dart';
import '../../../payments/data/payments_dao.dart';

/// Clears all app data except the service catalog.
/// Deletes: customers, appointments, bills, bill line items, payments.
class ResetAppDataUseCase {
  final CustomersDao _customersDao;
  final AppointmentsDao _appointmentsDao;
  final BillsDao _billsDao;
  final PaymentsDao _paymentsDao;

  ResetAppDataUseCase({
    required CustomersDao customersDao,
    required AppointmentsDao appointmentsDao,
    required BillsDao billsDao,
    required PaymentsDao paymentsDao,
  })  : _customersDao = customersDao,
        _appointmentsDao = appointmentsDao,
        _billsDao = billsDao,
        _paymentsDao = paymentsDao;

  Future<void> call() async {
    // Order: payments → bills → appointments → customers
    _paymentsDao.clear();
    _billsDao.clear();
    _appointmentsDao.clear();
    _customersDao.clear();
  }
}
