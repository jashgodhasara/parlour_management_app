import 'package:get_it/get_it.dart';

// DAOs
import '../../features/customers/data/customers_dao.dart';
import '../../features/services/data/services_dao.dart';
import '../../features/appointments/data/appointments_dao.dart';
import '../../features/billing/data/bills_dao.dart';
import '../../features/payments/data/payments_dao.dart';
import '../../features/settings/data/settings_dao.dart';
import '../../features/backup/data/drive_service_impl.dart';
import '../../features/appointments/data/notification_service_impl.dart';

// Repository implementations
import '../../features/customers/data/customer_repository_impl.dart';
import '../../features/services/data/service_catalog_repository_impl.dart';
import '../../features/appointments/data/appointment_repository_impl.dart';
import '../../features/billing/data/billing_repository_impl.dart';
import '../../features/payments/data/payment_repository_impl.dart';
import '../../features/reports/data/report_repository_impl.dart';
import '../../features/settings/data/settings_repository_impl.dart';
import '../../features/backup/data/backup_repository_impl.dart';

// Repository interfaces
import '../../features/customers/domain/customer_repository.dart';
import '../../features/services/domain/service_catalog_repository.dart';
import '../../features/appointments/domain/appointment_repository.dart';
import '../../features/billing/domain/billing_repository.dart';
import '../../features/payments/domain/payment_repository.dart';
import '../../features/reports/domain/report_repository.dart';
import '../../features/settings/domain/settings_repository.dart';
import '../../features/backup/domain/backup_repository.dart';
import '../../features/appointments/domain/notification_service.dart';
import '../../features/backup/domain/drive_service.dart';

// Customer use cases
import '../../features/customers/domain/use_cases/create_customer_use_case.dart';
import '../../features/customers/domain/use_cases/delete_all_customers_use_case.dart';
import '../../features/customers/domain/use_cases/delete_customer_use_case.dart';
import '../../features/customers/domain/use_cases/update_customer_use_case.dart';
import '../../features/customers/domain/use_cases/search_customers_use_case.dart';
import '../../features/customers/domain/use_cases/get_customer_by_id_use_case.dart';

// Service use cases
import '../../features/services/domain/use_cases/create_service_use_case.dart';
import '../../features/services/domain/use_cases/update_service_use_case.dart';
import '../../features/services/domain/use_cases/set_service_active_use_case.dart';

// Appointment use cases
import '../../features/appointments/domain/use_cases/create_appointment_use_case.dart';
import '../../features/appointments/domain/use_cases/update_appointment_use_case.dart';
import '../../features/appointments/domain/use_cases/cancel_appointment_use_case.dart';
import '../../features/appointments/domain/use_cases/detect_appointment_overlap_use_case.dart';
import '../../features/appointments/domain/use_cases/schedule_notification_use_case.dart';

// Billing use cases
import '../../features/billing/domain/use_cases/create_bill_use_case.dart';
import '../../features/billing/domain/use_cases/finalise_bill_use_case.dart';
import '../../features/billing/domain/use_cases/calculate_bill_total_use_case.dart';
import '../../features/billing/domain/use_cases/generate_bill_summary_use_case.dart';

// Payment use cases
import '../../features/payments/domain/use_cases/record_payment_use_case.dart';
import '../../features/payments/domain/use_cases/get_outstanding_balance_use_case.dart';

// Report use cases
import '../../features/reports/domain/use_cases/get_daily_summary_use_case.dart';
import '../../features/reports/domain/use_cases/get_monthly_summary_use_case.dart';
import '../../features/reports/domain/use_cases/get_yearly_summary_use_case.dart';
import '../../features/reports/domain/use_cases/generate_pdf_report_use_case.dart';
import '../../features/reports/domain/use_cases/generate_xlsx_statement_use_case.dart';

// Backup use cases
import '../../features/backup/domain/use_cases/backup_to_drive_use_case.dart';
import '../../features/backup/domain/use_cases/restore_from_drive_use_case.dart';
import '../../features/backup/domain/use_cases/export_data_use_case.dart';
import '../../features/backup/domain/use_cases/resolve_backup_conflict_use_case.dart';

// Settings use cases
import '../../features/settings/domain/use_cases/get_settings_use_case.dart';
import '../../features/settings/domain/use_cases/save_settings_use_case.dart';
import '../../features/settings/domain/use_cases/reset_app_data_use_case.dart';

// Home
import '../../features/home/presentation/home_cubit.dart';

// Customer presentation
import '../../features/customers/presentation/customer_detail_cubit.dart';
import '../../features/customers/presentation/customer_list_cubit.dart';
import '../../features/customers/presentation/customer_form_cubit.dart';

// Service presentation
import '../../features/services/presentation/service_catalog_cubit.dart';
import '../../features/services/presentation/service_form_cubit.dart';

// Billing presentation
import '../../features/billing/presentation/billing_cubit.dart';

final GetIt sl = GetIt.instance;

void configureDependencies() {
  // ── DAOs ──────────────────────────────────────────────────────────────────
  sl.registerLazySingleton<CustomersDao>(() => CustomersDao());
  sl.registerLazySingleton<ServicesDao>(() => ServicesDao());
  sl.registerLazySingleton<AppointmentsDao>(() => AppointmentsDao());
  sl.registerLazySingleton<BillsDao>(() => BillsDao());
  sl.registerLazySingleton<PaymentsDao>(() => PaymentsDao());
  sl.registerLazySingleton<SettingsDao>(() => SettingsDao());

  // ── Services ──────────────────────────────────────────────────────────────
  sl.registerLazySingleton<DriveService>(() => DriveServiceImpl());
  sl.registerLazySingleton<NotificationService>(
      () => NotificationServiceImpl());

  // ── Repositories ──────────────────────────────────────────────────────────
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(sl<SettingsDao>()),
  );
  sl.registerLazySingleton<CustomerRepository>(
    () => CustomerRepositoryImpl(sl<CustomersDao>()),
  );
  sl.registerLazySingleton<ServiceCatalogRepository>(
    () => ServiceCatalogRepositoryImpl(sl<ServicesDao>()),
  );
  sl.registerLazySingleton<AppointmentRepository>(
    () => AppointmentRepositoryImpl(sl<AppointmentsDao>(), sl<ServicesDao>()),
  );
  sl.registerLazySingleton<BillingRepository>(
    () => BillingRepositoryImpl(sl<BillsDao>(), sl<ServicesDao>()),
  );
  sl.registerLazySingleton<PaymentRepository>(
    () => PaymentRepositoryImpl(sl<PaymentsDao>(), sl<BillingRepository>()),
  );
  sl.registerLazySingleton<ReportRepository>(
    () => ReportRepositoryImpl(
      sl<BillingRepository>(),
      sl<PaymentRepository>(),
      sl<CustomersDao>(),
    ),
  );
  sl.registerLazySingleton<BackupRepository>(
    () => BackupRepositoryImpl(
      customersDao: sl<CustomersDao>(),
      servicesDao: sl<ServicesDao>(),
      billsDao: sl<BillsDao>(),
      paymentsDao: sl<PaymentsDao>(),
      driveService: sl<DriveService>(),
      settingsRepository: sl<SettingsRepository>(),
    ),
  );

  // ── Use Cases ─────────────────────────────────────────────────────────────

  // Customers
  sl.registerFactory(() => CreateCustomerUseCase(sl<CustomerRepository>()));
  sl.registerFactory(() => UpdateCustomerUseCase(sl<CustomerRepository>()));
  sl.registerFactory(() => DeleteCustomerUseCase(sl<CustomerRepository>()));
  sl.registerFactory(() => DeleteAllCustomersUseCase(sl<CustomerRepository>()));
  sl.registerFactory(() => SearchCustomersUseCase(sl<CustomerRepository>()));
  sl.registerFactory(() => GetCustomerByIdUseCase(sl<CustomerRepository>()));

  // Services
  sl.registerFactory(
      () => CreateServiceUseCase(sl<ServiceCatalogRepository>()));
  sl.registerFactory(
      () => UpdateServiceUseCase(sl<ServiceCatalogRepository>()));
  sl.registerFactory(
      () => SetServiceActiveUseCase(sl<ServiceCatalogRepository>()));

  // Appointments
  sl.registerFactory(
      () => CreateAppointmentUseCase(sl<AppointmentRepository>()));
  sl.registerFactory(
      () => UpdateAppointmentUseCase(sl<AppointmentRepository>()));
  sl.registerFactory(
      () => CancelAppointmentUseCase(sl<AppointmentRepository>()));
  sl.registerFactory(
      () => DetectAppointmentOverlapUseCase(sl<AppointmentRepository>()));
  sl.registerFactory(
      () => ScheduleNotificationUseCase(sl<NotificationService>()));

  // Billing
  sl.registerFactory(() => CreateBillUseCase(sl<BillingRepository>()));
  sl.registerFactory(() => FinaliseBillUseCase(sl<BillingRepository>()));
  sl.registerFactory(() => const CalculateBillTotalUseCase());
  sl.registerFactory(
      () => GenerateBillSummaryUseCase(sl<SettingsRepository>()));

  // Payments
  sl.registerFactory(() =>
      RecordPaymentUseCase(sl<PaymentRepository>(), sl<BillingRepository>()));
  sl.registerFactory(
      () => GetOutstandingBalanceUseCase(sl<PaymentRepository>()));

  // Reports
  sl.registerFactory(() => GetDailySummaryUseCase(sl<ReportRepository>()));
  sl.registerFactory(() => GetMonthlySummaryUseCase(sl<ReportRepository>()));
  sl.registerFactory(() => GetYearlySummaryUseCase(sl<ReportRepository>()));
  sl.registerFactory(() => GeneratePdfReportUseCase(
      sl<ReportRepository>(), sl<SettingsRepository>()));
  sl.registerFactory(
      () => GenerateXlsxStatementUseCase(sl<ReportRepository>()));

  // Backup
  sl.registerFactory(() => BackupToDriveUseCase(sl<BackupRepository>()));
  sl.registerFactory(() => RestoreFromDriveUseCase(sl<BackupRepository>()));
  sl.registerFactory(() => ExportDataUseCase(sl<BackupRepository>()));
  sl.registerFactory(() => const ResolveBackupConflictUseCase());

  // Settings
  sl.registerFactory(() => GetSettingsUseCase(sl<SettingsRepository>()));
  sl.registerFactory(() => SaveSettingsUseCase(sl<SettingsRepository>()));
  sl.registerFactory(() => ResetAppDataUseCase(
        customersDao: sl<CustomersDao>(),
        appointmentsDao: sl<AppointmentsDao>(),
        billsDao: sl<BillsDao>(),
        paymentsDao: sl<PaymentsDao>(),
      ));

  // Home
  sl.registerFactory(() => HomeCubit(
        appointmentRepository: sl<AppointmentRepository>(),
        reportRepository: sl<ReportRepository>(),
        settingsRepository: sl<SettingsRepository>(),
      ));

  // Customer presentation
  sl.registerFactory(() => CustomerListCubit(
        searchCustomersUseCase: sl<SearchCustomersUseCase>(),
        getCustomerByIdUseCase: sl<GetCustomerByIdUseCase>(),
        deleteCustomerUseCase: sl<DeleteCustomerUseCase>(),
        deleteAllCustomersUseCase: sl<DeleteAllCustomersUseCase>(),
      ));

  sl.registerFactoryParam<CustomerFormCubit, String?, void>(
    (customerId, _) => CustomerFormCubit(
      createCustomerUseCase: sl<CreateCustomerUseCase>(),
      updateCustomerUseCase: sl<UpdateCustomerUseCase>(),
      getCustomerByIdUseCase: sl<GetCustomerByIdUseCase>(),
      customerId: customerId,
    ),
  );

  sl.registerFactoryParam<CustomerDetailCubit, String, void>(
    (customerId, _) => CustomerDetailCubit(
      customerId: customerId,
      getCustomerByIdUseCase: sl<GetCustomerByIdUseCase>(),
      getOutstandingBalanceUseCase: sl<GetOutstandingBalanceUseCase>(),
      billingRepository: sl<BillingRepository>(),
      deleteCustomerUseCase: sl<DeleteCustomerUseCase>(),
    ),
  );

  // Services presentation
  sl.registerFactory(() => ServiceCatalogCubit(
        serviceCatalogRepository: sl<ServiceCatalogRepository>(),
        setServiceActiveUseCase: sl<SetServiceActiveUseCase>(),
      ));

  sl.registerFactoryParam<ServiceFormCubit, String?, void>(
    (serviceId, _) => ServiceFormCubit(
      serviceCatalogRepository: sl<ServiceCatalogRepository>(),
      createServiceUseCase: sl<CreateServiceUseCase>(),
      updateServiceUseCase: sl<UpdateServiceUseCase>(),
      serviceId: serviceId,
    ),
  );

  // Billing presentation
  sl.registerFactoryParam<BillingCubit, String?, void>(
    (customerId, _) => BillingCubit(
      serviceCatalogRepository: sl<ServiceCatalogRepository>(),
      createBillUseCase: sl<CreateBillUseCase>(),
      finaliseBillUseCase: sl<FinaliseBillUseCase>(),
      customerId: customerId,
    ),
  );
}
