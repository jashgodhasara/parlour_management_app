import 'dart:async';
import 'dart:convert';

import 'package:excel/excel.dart' as xlsx;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as phone_contacts;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'core/database/local_app_store.dart';
import 'customer_seed_data.dart';
import 'features/appointments/presentation/online_bookings_screen.dart';
import 'screen/screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.light);

const _googleSignInServerClientId = String.fromEnvironment(
  'GOOGLE_SIGN_IN_SERVER_CLIENT_ID',
  defaultValue:
      '817834154794-e92ki959vturl8ak03djp5gskv8a1736.apps.googleusercontent.com',
);

@pragma('vm:entry-point')
void notificationTapBackground(
    NotificationResponse notificationResponse) async {
  if (notificationResponse.actionId == 'call_action' &&
      notificationResponse.payload != null &&
      notificationResponse.payload!.isNotEmpty) {
    final url = Uri.parse('tel:${notificationResponse.payload}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }
}

int _appointmentNotificationId(Appointment appointment) {
  return Object.hash(
        appointment.customerName,
        appointment.serviceName,
        appointment.date.year,
        appointment.date.month,
        appointment.date.day,
        appointment.time.hour,
        appointment.time.minute,
      ) &
      0x7fffffff;
}

Future<void> scheduleAppointmentNotification(
  Appointment appointment,
  String phone, {
  required bool enabled,
  required int reminderMinutes,
}) async {
  if (kIsWeb) return;
  if (!enabled) return;

  final appointmentTime = DateTime(
    appointment.date.year,
    appointment.date.month,
    appointment.date.day,
    appointment.time.hour,
    appointment.time.minute,
  );
  final reminderTime = appointmentTime.subtract(
    Duration(minutes: reminderMinutes),
  );

  final now = DateTime.now();

  final tz.TZDateTime scheduledDate = reminderTime.isBefore(now)
      ? tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5))
      : tz.TZDateTime.from(reminderTime, tz.local);

  final hasPhone = phone.trim().isNotEmpty;
  final title = reminderMinutes > 0 ? 'Booking reminder' : 'Booking time';

  await flutterLocalNotificationsPlugin.zonedSchedule(
    id: _appointmentNotificationId(appointment),
    title: title,
    body:
        '${appointment.customerName} - ${appointment.serviceName}. Open app for actions.',
    scheduledDate: scheduledDate,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'appointment_channel',
        'Appointments',
        channelDescription: 'Notifications for booking time',
        importance: Importance.max,
        priority: Priority.high,
        actions: hasPhone
            ? const <AndroidNotificationAction>[
                AndroidNotificationAction(
                  'call_action',
                  'Call Customer',
                  showsUserInterface: true,
                ),
              ]
            : null,
      ),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: hasPhone ? 'appointment_actions' : null,
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: hasPhone ? phone.trim() : null,
  );
}

Future<void> cancelAppointmentNotification(Appointment appointment) async {
  if (kIsWeb) return;
  await flutterLocalNotificationsPlugin.cancel(
    id: _appointmentNotificationId(appointment),
  );
}

// ── Daily morning summary notification ───────────────────────────────────────

const int _dailySummaryNotificationId = 999001;

/// Schedules (or re-schedules) the 9:00 AM daily summary notification.
/// Shows total appointments for today and the first customer's time.
/// Call this whenever appointments change or on app start.
Future<void> scheduleDailySummaryNotification(
    List<Appointment> appointments) async {
  if (kIsWeb) return;

  // Cancel any previously scheduled daily summary.
  await flutterLocalNotificationsPlugin.cancel(
    id: _dailySummaryNotificationId,
  );

  final now = DateTime.now();

  // Determine next 9:00 AM — today if it's still before 9 AM, else tomorrow.
  DateTime next9am = DateTime(now.year, now.month, now.day, 9, 0);
  if (now.isAfter(next9am)) {
    next9am = next9am.add(const Duration(days: 1));
  }

  // Find appointments for the target day (tomorrow if we already passed 9 AM today).
  final targetDate = next9am;
  final todaysAppointments = appointments.where((a) {
    return a.date.year == targetDate.year &&
        a.date.month == targetDate.month &&
        a.date.day == targetDate.day &&
        a.status != 'Cancelled';
  }).toList()
    ..sort((a, b) {
      final aMin = a.time.hour * 60 + a.time.minute;
      final bMin = b.time.hour * 60 + b.time.minute;
      return aMin.compareTo(bMin);
    });

  // Only schedule if there is at least one appointment.
  if (todaysAppointments.isEmpty) return;

  final count = todaysAppointments.length;
  final first = todaysAppointments.first;
  final firstTime = _formatTime(first.time);

  final title =
      '📅 Today\'s Schedule — $count appointment${count == 1 ? '' : 's'}';
  final body = 'First customer: ${first.customerName} at $firstTime';

  final scheduledDate = tz.TZDateTime.from(next9am, tz.local);

  await flutterLocalNotificationsPlugin.zonedSchedule(
    id: _dailySummaryNotificationId,
    title: title,
    body: body,
    scheduledDate: scheduledDate,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_summary_channel',
        'Daily Summary',
        channelDescription: 'Morning summary of today\'s appointments',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  );
}

String _formatTime(TimeOfDay time) {
  final hour = time.hour;
  final minute = time.minute;
  final period = hour < 12 ? 'AM' : 'PM';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  final minuteStr = minute.toString().padLeft(2, '0');
  return '$displayHour:$minuteStr $period';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await _initializeGoogleSignIn();

  if (!kIsWeb) {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/launch_background');
    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          'appointment_actions',
          actions: [
            DarwinNotificationAction.plain('call_action', 'Call Customer'),
          ],
        ),
      ],
    );
    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.actionId == 'call_action' &&
            response.payload != null &&
            response.payload!.isNotEmpty) {
          final url = Uri.parse('tel:${response.payload}');
          if (await canLaunchUrl(url)) {
            await launchUrl(url);
          }
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
  }

  runApp(
    const ParlourManagementApp(
      phonePreview: bool.fromEnvironment('PHONE_PREVIEW'),
    ),
  );
}

Future<void> _initializeGoogleSignIn() async {
  if (_googleSignInServerClientId.isEmpty) return;

  try {
    await GoogleSignIn.instance.initialize(
      serverClientId: _googleSignInServerClientId,
    );
  } catch (_) {
    // Backup/restore buttons will report configuration errors when used.
  }
}

class ParlourManagementApp extends StatelessWidget {
  const ParlourManagementApp({super.key, this.phonePreview = false});

  final bool phonePreview;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff0f766e);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Nupur Beauty Parlour',
          debugShowCheckedModeBanner: false,
          builder: phonePreview
              ? (context, child) => IphonePasscodeScreen(child: child)
              : null,
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff0369A1),
              brightness: Brightness.light,
              primary: const Color(0xff0369A1),
              secondary: const Color(0xff38BDF8),
              tertiary: const Color(0xff0369A1),
              surface: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xffF0F7FF),
            dialogBackgroundColor: const Color(0xffF0F7FF),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xffF0F7FF),
              surfaceTintColor: Colors.transparent,
              elevation: 12,
              shadowColor: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: const Color(0xff0369A1).withOpacity(0.2),
                  width: 1.2,
                ),
              ),
              titleTextStyle: const TextStyle(
                color: Color(0xff0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
              contentTextStyle: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 14,
              ),
            ),
            bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: const Color(0xffF0F7FF),
              surfaceTintColor: Colors.transparent,
              elevation: 16,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                side: BorderSide(
                  color: const Color(0xff0369A1).withOpacity(0.15),
                  width: 1.2,
                ),
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              headerBackgroundColor: const Color(0xff0369A1),
              headerForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: const Color(0xff0369A1).withOpacity(0.2),
                  width: 1.2,
                ),
              ),
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: const Color(0xff0369A1).withOpacity(0.2),
                  width: 1.2,
                ),
              ),
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: Color(0xff0F172A),
              iconTheme: IconThemeData(color: Color(0xff0F172A)),
            ),
            navigationBarTheme: const NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: Color(0xffE0F2FE),
            ),
            cardTheme: CardThemeData(
              elevation: 2,
              shadowColor: Colors.black12,
              color: Colors.white,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: const Color(0xff0369A1).withOpacity(0.15),
                  width: 1,
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xffF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: const Color(0xff0369A1).withOpacity(0.25),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xffCBD5E1),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xff0369A1),
                  width: 1.8,
                ),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff38BDF8),
              brightness: Brightness.dark,
              primary: const Color(0xff38BDF8),
              secondary: const Color(0xff0EA5E9),
              tertiary: const Color(0xff67E8F9),
              surface: const Color(0xff1E293B),
            ),
            scaffoldBackgroundColor: const Color(0xff0F172A),
            dialogBackgroundColor: const Color(0xff1E293B),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xff1E293B),
              surfaceTintColor: Colors.transparent,
              elevation: 16,
              shadowColor: Colors.black54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: const Color(0xff38BDF8).withOpacity(0.25),
                  width: 1.2,
                ),
              ),
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
              contentTextStyle: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 14,
              ),
            ),
            bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: const Color(0xff1E293B),
              surfaceTintColor: Colors.transparent,
              elevation: 16,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                side: BorderSide(
                  color: const Color(0xff38BDF8).withOpacity(0.2),
                  width: 1.2,
                ),
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: const Color(0xff1E293B),
              surfaceTintColor: Colors.transparent,
              headerBackgroundColor: const Color(0xff0369A1),
              headerForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: const Color(0xff38BDF8).withOpacity(0.25),
                  width: 1.2,
                ),
              ),
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: const Color(0xff1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: const Color(0xff38BDF8).withOpacity(0.25),
                  width: 1.2,
                ),
              ),
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              backgroundColor: Color(0xff0F172A),
              foregroundColor: Color(0xffF8FAFC),
            ),
            navigationBarTheme: const NavigationBarThemeData(
              backgroundColor: Color(0xff0F172A),
              indicatorColor: Color(0xff0369A1),
            ),
            cardTheme: CardThemeData(
              elevation: 4,
              shadowColor: Colors.black26,
              color: const Color(0xff1E293B),
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: const Color(0xff38BDF8).withOpacity(0.18),
                  width: 1,
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xff0F172A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: const Color(0xff38BDF8).withOpacity(0.25),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xff334155),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xff38BDF8),
                  width: 1.8,
                ),
              ),
            ),
          ),
          home: const ParlourHome(),
        );
      },
    );
  }
}

class ParlourHome extends StatefulWidget {
  const ParlourHome({super.key});

  @override
  State<ParlourHome> createState() => _ParlourHomeState();
}

class _ShopSettings {
  const _ShopSettings({
    required this.parlourName,
    required this.ownerName,
    required this.shopPhone,
    required this.shopAddress,
    required this.openingTime,
    required this.closingTime,
    required this.bookingReminderEnabled,
    required this.reminderMinutes,
    required this.autoBackupEnabled,
    required this.backupEmail,
    required this.invoiceFooter,
    required this.darkModeEnabled,
    required this.greenApiUrl,
    required this.greenApiInstanceId,
    required this.greenApiToken,
  });

  factory _ShopSettings.fromJson(
    Map<String, dynamic> json,
    _ShopSettings fallback,
  ) {
    return _ShopSettings(
      parlourName: (json['parlourName'] as String?) ?? fallback.parlourName,
      ownerName: (json['ownerName'] as String?) ?? fallback.ownerName,
      shopPhone: (json['shopPhone'] as String?) ?? fallback.shopPhone,
      shopAddress: (json['shopAddress'] as String?) ?? fallback.shopAddress,
      openingTime: (json['openingTime'] as String?) ?? fallback.openingTime,
      closingTime: (json['closingTime'] as String?) ?? fallback.closingTime,
      bookingReminderEnabled: (json['bookingReminderEnabled'] as bool?) ??
          fallback.bookingReminderEnabled,
      reminderMinutes: (json['reminderMinutes'] as num?)?.toInt() ??
          fallback.reminderMinutes,
      autoBackupEnabled:
          (json['autoBackupEnabled'] as bool?) ?? fallback.autoBackupEnabled,
      backupEmail: (json['backupEmail'] as String?) ?? fallback.backupEmail,
      invoiceFooter:
          (json['invoiceFooter'] as String?) ?? fallback.invoiceFooter,
      darkModeEnabled:
          (json['darkModeEnabled'] as bool?) ?? fallback.darkModeEnabled,
      greenApiUrl: (json['greenApiUrl'] as String?) ?? fallback.greenApiUrl,
      greenApiInstanceId: (json['greenApiInstanceId'] as String?) ??
          fallback.greenApiInstanceId,
      greenApiToken:
          (json['greenApiToken'] as String?) ?? fallback.greenApiToken,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'parlourName': parlourName,
      'ownerName': ownerName,
      'shopPhone': shopPhone,
      'shopAddress': shopAddress,
      'openingTime': openingTime,
      'closingTime': closingTime,
      'bookingReminderEnabled': bookingReminderEnabled,
      'reminderMinutes': reminderMinutes,
      'autoBackupEnabled': autoBackupEnabled,
      'backupEmail': backupEmail,
      'invoiceFooter': invoiceFooter,
      'darkModeEnabled': darkModeEnabled,
      'greenApiUrl': greenApiUrl,
      'greenApiInstanceId': greenApiInstanceId,
      'greenApiToken': greenApiToken,
    };
  }

  final String parlourName;
  final String ownerName;
  final String shopPhone;
  final String shopAddress;
  final String openingTime;
  final String closingTime;
  final bool bookingReminderEnabled;
  final int reminderMinutes;
  final bool autoBackupEnabled;
  final String backupEmail;
  final String invoiceFooter;
  final bool darkModeEnabled;
  final String greenApiUrl;
  final String greenApiInstanceId;
  final String greenApiToken;
}

class _ParlourHomeState extends State<ParlourHome> with WidgetsBindingObserver {
  static const _storageKey = 'parlour_home_state_v1';
  static const _backupAccountKey = 'parlour_backup_google_account';
  static const _dailyBackupDateKey = 'parlour_daily_google_backup_date';
  static const _backupChannel = MethodChannel('parlour_management_app/backup');
  static const _shareChannel = MethodChannel('parlour_management_app/share');
  static const _driveBackupFileName = 'nupur_beauty_parlour_backup.json';
  static const _driveScopes = <String>[drive.DriveApi.driveAppdataScope];
  static const _defaultBackupEmail = 'jashgodhasara06@gmail.com';
  final LocalAppStore _localStore = LocalAppStore();

  final List<Customer> _customers = [];

  final List<ParlourService> _services = [
    ParlourService('Eyebrow', 'Threading', 0, 10),
    ParlourService('Upper Lips', 'Threading', 0, 5),
    ParlourService('Cleanup', 'Facial', 0, 30),
    ParlourService('Facial', 'Facial', 0, 30),
    ParlourService('Wax', 'Wax', 0, 20),
    ParlourService('Hair Smoothening', 'Hair', 0, 180),
    ParlourService('Hair Spa', 'Hair', 0, 60),
    ParlourService('Hair Cut', 'Hair', 0, 30),
    ParlourService('Clurs', 'Hair', 0, 30),
    ParlourService('Strating', 'Hair', 0, 30),
    ParlourService('Color Hina', 'Color Hina', 0, 30),
    ParlourService('Others', 'Others', 0, 30),
  ];

  final List<Appointment> _appointments = [];

  final List<Bill> _bills = [];

  final List<PurchaseItem> _purchases = [];

  final List<InvestmentTransaction> _investments = [];

  int _tabIndex = 0;
  String _parlourName = 'Nupur Beauty Parlour';
  String _ownerName = 'Mummy';
  String _shopPhone = '';
  String _shopAddress = '';
  String _openingTime = '10:00 AM';
  String _closingTime = '8:00 PM';
  bool _bookingReminderEnabled = true;
  int _reminderMinutes = 0;
  bool _autoBackupEnabled = false;
  String _backupEmail = _defaultBackupEmail;
  String _invoiceFooter = 'Thank you.';
  bool _darkModeEnabled = false;
  String _greenApiUrl = 'https://api.green-api.com';
  String _greenApiInstanceId = '7107633059';
  String _greenApiToken = '44c582a9853941b598beb75517967c3c2126378b0a7a443da9';
  bool _restorePromptShown = false;
  Timer? _greenApiNotificationTimer;
  bool _checkingGreenApiNotifications = false;

  _ShopSettings get _shopSettings => _ShopSettings(
        parlourName: _parlourName,
        ownerName: _ownerName,
        shopPhone: _shopPhone,
        shopAddress: _shopAddress,
        openingTime: _openingTime,
        closingTime: _closingTime,
        bookingReminderEnabled: _bookingReminderEnabled,
        reminderMinutes: _reminderMinutes,
        autoBackupEnabled: _autoBackupEnabled,
        backupEmail: _backupEmail,
        invoiceFooter: _invoiceFooter,
        darkModeEnabled: _darkModeEnabled,
        greenApiUrl: _greenApiUrl,
        greenApiInstanceId: _greenApiInstanceId,
        greenApiToken: _greenApiToken,
      );

  void _applyShopSettings(_ShopSettings settings) {
    _parlourName = settings.parlourName;
    _ownerName = settings.ownerName;
    _shopPhone = settings.shopPhone;
    _shopAddress = settings.shopAddress;
    _openingTime = settings.openingTime;
    _closingTime = settings.closingTime;
    _bookingReminderEnabled = settings.bookingReminderEnabled;
    _reminderMinutes = settings.reminderMinutes;
    _autoBackupEnabled = settings.autoBackupEnabled;
    _backupEmail = settings.backupEmail.trim().isEmpty
        ? _defaultBackupEmail
        : settings.backupEmail.trim();
    _invoiceFooter = settings.invoiceFooter;
    _darkModeEnabled = settings.darkModeEnabled;
    _greenApiUrl = settings.greenApiUrl.trim().isEmpty
        ? 'https://api.green-api.com'
        : settings.greenApiUrl.trim();
    _greenApiInstanceId = settings.greenApiInstanceId.trim().isEmpty
        ? '7107633059'
        : settings.greenApiInstanceId.trim();
    _greenApiToken = settings.greenApiToken.trim().isEmpty
        ? '44c582a9853941b598beb75517967c3c2126378b0a7a443da9'
        : settings.greenApiToken.trim();
    appThemeMode.value =
        settings.darkModeEnabled ? ThemeMode.dark : ThemeMode.light;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedState();
    _greenApiNotificationTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_checkGreenApiNotifications()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _greenApiNotificationTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_tryScheduledDailyGoogleBackup());
      unawaited(_checkGreenApiNotifications());
      unawaited(scheduleDailySummaryNotification(_appointments));
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveState());
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardPage(
        parlourName: _parlourName,
        appointments: _appointments,
        bills: _bills,
        purchases: _purchases,
        investments: _investments,
        customers: _customers,
        onQuickAction: _openQuickAction,
        onOpenTab: (index) => setState(() => _tabIndex = index),
        onShareBackup: () async {
          try {
            final msg = await _shareLocalBackup();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Share failed: $e'), backgroundColor: Colors.red),
            );
          }
        },
        onImportBackup: () async {
          try {
            final msg = await _importLocalBackup();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), backgroundColor: Colors.green),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
            );
          }
        },
      ),
      _CustomersPage(
          customers: _customers,
          bills: _bills,
          appointments: _appointments,
          onAddCustomer: _addCustomer,
          onImportCustomers: _importCustomersFromExcel,
          onImportPhoneContacts: _importCustomersFromPhoneContacts,
          onEditCustomer: _editCustomer,
          onDeleteCustomer: _deleteCustomer,
          onDeleteAllCustomers: () {
            setState(() => _customers.clear());
            _saveState();
          },
          onDeleteMultiple: (toDelete) {
            setState(() {
              for (final c in toDelete) {
                _customers.remove(c);
              }
            });
            _saveState();
          },
          onUpdateCustomer: _updateCustomer,
          onAddBill: (customer) => _addBill(forCustomer: customer)),
      _AppointmentsPage(
          appointments: _appointments,
          parlourName: _parlourName,
          shopPhone: _shopPhone,
          shopAddress: _shopAddress,
          onAddAppointment: () => _addAppointment(),
          onAddAppointmentForDate: (date) => _addAppointment(initialDate: date),
          onOpenOnlineBookings: _openOnlineBookingsScreen,
          onAddConfirmedOnlineBooking: _addConfirmedOnlineBooking,
          onEditAppointment: _editAppointment,
          onConfirmAppointment: _confirmAppointment,
          onMarkArrived: _markAppointmentArrived,
          onDeleteAppointment: _deleteAppointment),
      _BillingPage(
        bills: _bills,
        onAddBill: _addBill,
        onEditBill: _editBill,
        onDeleteBill: _deleteBill,
        onShareBill: _shareBillPdfToClientWhatsApp,
        onExportBill: _exportBillPdf,
      ),
      _ServicesPage(
          services: _services,
          onAddService: _addService,
          onEditService: _editService,
          onDeleteService: _deleteService),
      _PurchasesPage(
        purchases: _purchases,
        onAddPurchase: _addPurchase,
        onEditPurchase: _editPurchase,
        onDeletePurchase: _deletePurchase,
      ),
      _InvestmentsPage(
        investments: _investments,
        onAddInvestment: _addInvestment,
        onEditInvestment: _editInvestment,
        onDeleteInvestment: _deleteInvestment,
      ),
      _ReportsPage(
        customers: _customers,
        bills: _bills,
        appointments: _appointments,
        onShareBill: _shareBillPdfToClientWhatsApp,
        onExportBill: _exportBillPdf,
      ),
      _SettingsPage(
        settings: _shopSettings,
        onSave: (settings) async {
          setState(() => _applyShopSettings(settings));
          unawaited(_configureGreenApiNotifications());
          await _saveState();
        },
        onConnectGoogle: _connectGmailForBackup,
        onBackup: _backupToGoogleDrive,
        onRestore: _restoreFromGoogleDrive,
        onShareLocalBackup: _shareLocalBackup,
        onImportLocalBackup: _importLocalBackup,
        onCleanPhoneFromNotes: _cleanPhoneFromNotes,
      ),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_tabIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        elevation: 20,
        shadowColor: Colors.black26,
        backgroundColor: Theme.of(context).navigationBarTheme.backgroundColor,
        indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(0.18),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Clients'),
          NavigationDestination(
              icon: Icon(Icons.event_outlined),
              selectedIcon: Icon(Icons.event),
              label: 'Bookings'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Bills'),
          NavigationDestination(
              icon: Icon(Icons.content_cut), label: 'Services'),
          NavigationDestination(
              icon: Icon(Icons.shopping_bag_outlined),
              selectedIcon: Icon(Icons.shopping_bag),
              label: 'Purchases'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Invest'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Reports'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }

  Future<void> _openQuickAction(String action) async {
    switch (action) {
      case 'customer':
        await _addCustomer();
        break;
      case 'appointment':
        await _addAppointment();
        break;
      case 'bill':
        await _addBill();
        break;
      case 'invest':
        await _addInvestment();
        break;
    }
  }

  Future<void> _addCustomer() async {
    final result = await showDialog<Customer>(
      context: context,
      builder: (context) => const _CustomerDialog(),
    );
    if (result == null) return;
    setState(() => _customers.add(result));
    await _saveState();
  }

  Future<void> _importCustomersFromExcel() async {
    const excelType = XTypeGroup(
      label: 'Excel contacts',
      extensions: ['xlsx'],
      mimeTypes: [
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ],
    );

    try {
      final file = await openFile(acceptedTypeGroups: [excelType]);
      if (file == null) return;

      final importedCustomers =
          _readCustomersFromExcel(await file.readAsBytes());
      if (importedCustomers.isEmpty) {
        _showMessage(
          'No contacts found. Use columns: Name, Phone, Notes, Referred By.',
        );
        return;
      }

      var added = 0;
      var skipped = 0;
      final existingPhones = _customers
          .map((customer) => _normalizePhone(customer.phone))
          .where((phone) => phone.isNotEmpty)
          .toSet();
      final existingNamePhone = _customers
          .map((customer) =>
              '${customer.name.trim().toLowerCase()}|${_normalizePhone(customer.phone)}')
          .toSet();
      final customersToAdd = <Customer>[];

      for (final customer in importedCustomers) {
        final phone = _normalizePhone(customer.phone);
        final namePhone = '${customer.name.trim().toLowerCase()}|$phone';
        final isDuplicate = phone.isNotEmpty
            ? existingPhones.contains(phone)
            : existingNamePhone.contains(namePhone);
        if (isDuplicate) {
          skipped++;
          continue;
        }

        existingPhones.add(phone);
        existingNamePhone.add(namePhone);
        customersToAdd.add(customer);
        added++;
      }

      if (customersToAdd.isEmpty) {
        _showMessage(
            'No new contacts imported. $skipped duplicate(s) skipped.');
        return;
      }

      setState(() => _customers.addAll(customersToAdd));
      await _saveState();
      _showMessage(
        'Imported $added contact${added == 1 ? '' : 's'}'
        '${skipped > 0 ? ', skipped $skipped duplicate${skipped == 1 ? '' : 's'}' : ''}.',
      );
    } catch (error) {
      _showMessage('Could not import Excel contacts: $error');
    }
  }

  Future<void> _importCustomersFromPhoneContacts() async {
    if (kIsWeb) {
      _showMessage('Phone contacts import works on Android or iPhone.');
      return;
    }

    try {
      final granted = await phone_contacts.FlutterContacts.requestPermission(
          readonly: true);
      if (!granted) {
        _showMessage('Contacts permission was not allowed.');
        return;
      }

      final contacts = await phone_contacts.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      final phoneChoices = <_PhoneContactCustomer>[];
      final seenPhones = <String>{};

      for (final contact in contacts) {
        final name = contact.displayName.trim();
        for (final phone in contact.phones) {
          final phoneNumber = phone.number.trim();
          final normalizedPhone = _normalizePhone(phoneNumber);
          if (normalizedPhone.isEmpty || seenPhones.contains(normalizedPhone)) {
            continue;
          }

          seenPhones.add(normalizedPhone);
          phoneChoices.add(
            _PhoneContactCustomer(
              name: name.isEmpty ? phoneNumber : name,
              phone: phoneNumber,
            ),
          );
        }
      }

      if (phoneChoices.isEmpty) {
        _showMessage('No phone contacts found.');
        return;
      }

      phoneChoices.sort((a, b) => a.name.compareTo(b.name));
      final selected = await showDialog<List<_PhoneContactCustomer>>(
        context: context,
        builder: (context) => _PhoneContactImportDialog(
          contacts: phoneChoices,
          existingCustomers: _customers,
          normalizePhone: _normalizePhone,
        ),
      );
      if (selected == null || selected.isEmpty) return;

      final existingPhones = _customers
          .map((customer) => _normalizePhone(customer.phone))
          .where((phone) => phone.isNotEmpty)
          .toSet();
      final existingNamePhone = _customers
          .map((customer) =>
              '${customer.name.trim().toLowerCase()}|${_normalizePhone(customer.phone)}')
          .toSet();
      final customersToAdd = <Customer>[];
      var skipped = 0;

      for (var i = 0; i < selected.length; i++) {
        final contact = selected[i];
        final phone = _normalizePhone(contact.phone);
        final namePhone = '${contact.name.trim().toLowerCase()}|$phone';
        final isDuplicate = phone.isNotEmpty
            ? existingPhones.contains(phone)
            : existingNamePhone.contains(namePhone);
        if (isDuplicate) {
          skipped++;
          continue;
        }

        existingPhones.add(phone);
        existingNamePhone.add(namePhone);
        customersToAdd.add(
          Customer(
            'C-${DateTime.now().microsecondsSinceEpoch}-$i',
            contact.name,
            contact.phone,
            'Imported from phone contacts',
          ),
        );
      }

      if (customersToAdd.isEmpty) {
        _showMessage(
            'No new phone contacts added. $skipped duplicate(s) skipped.');
        return;
      }

      setState(() => _customers.addAll(customersToAdd));
      await _saveState();
      _showMessage(
        'Added ${customersToAdd.length} phone contact'
        '${customersToAdd.length == 1 ? '' : 's'} to app'
        '${skipped > 0 ? ', skipped $skipped duplicate${skipped == 1 ? '' : 's'}' : ''}.',
      );
    } catch (error) {
      _showMessage('Could not import phone contacts: $error');
    }
  }

  List<Customer> _readCustomersFromExcel(List<int> bytes) {
    final workbook = xlsx.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return [];

    // Pick the sheet that has a recognizable header row.
    // Fall back to the first sheet if none has a header.
    String sheetName = workbook.tables.keys.first;
    int? bestHeaderIndex;
    for (final name in workbook.tables.keys) {
      final rows = workbook.tables[name]?.rows ?? const <List<xlsx.Data?>>[];
      final headerIndex = _findCustomerHeaderRow(rows);
      if (headerIndex != null) {
        sheetName = name;
        bestHeaderIndex = headerIndex;
        break;
      }
    }

    final rows = workbook.tables[sheetName]?.rows ?? const <List<xlsx.Data?>>[];
    if (rows.isEmpty) return [];

    final headerIndex = bestHeaderIndex ?? _findCustomerHeaderRow(rows);
    final columns = headerIndex == null
        ? const _CustomerImportColumns(
            name: 0, phone: 1, note: 2, referredBy: 3)
        : _columnsFromHeader(rows[headerIndex]);
    final startRow = headerIndex == null ? 0 : headerIndex + 1;
    final imported = <Customer>[];

    for (var i = startRow; i < rows.length; i++) {
      final row = rows[i];
      final name = _cellText(_cellAt(row, columns.name)).trim();
      if (name.isEmpty) continue;

      // Read phone from detected column first
      String rawPhone = _cellText(_cellAt(row, columns.phone)).trim();

      // If phone column is empty or looks like notes (letters present),
      // scan all cells in this row to find one that looks like a phone number
      if (!_looksLikePhone(rawPhone)) {
        for (var col = 0; col < row.length; col++) {
          if (col == columns.name) continue; // skip name column
          final candidate = _cellText(row[col]).trim();
          if (_looksLikePhone(candidate)) {
            rawPhone = candidate;
            break;
          }
        }
      }

      // Clean phone: remove spaces, dashes, and trailing .0
      final phone = rawPhone
          .replaceAll(' ', '')
          .replaceAll('-', '')
          .replaceAll(RegExp(r'\.0$'), '');

      // Only put into note if it's clearly not a phone number
      // AND it's not the same column as phone
      final rawNote = columns.note != columns.phone
          ? _cellText(_cellAt(row, columns.note)).trim()
          : '';
      final note = _looksLikePhone(rawNote) ? '' : rawNote;
      // Never let referredBy be a phone number either
      final rawRef = columns.referredBy != columns.phone
          ? _cellText(_cellAt(row, columns.referredBy)).trim()
          : '';
      final referredBy = _looksLikePhone(rawRef) ? '' : rawRef;

      imported.add(Customer(
        'C-${DateTime.now().microsecondsSinceEpoch}-$i',
        name,
        phone,
        note,
        referredBy: referredBy,
      ));
    }

    return imported;
  }

  int? _findCustomerHeaderRow(List<List<xlsx.Data?>> rows) {
    final limit = rows.length < 10 ? rows.length : 10;
    for (var rowIndex = 0; rowIndex < limit; rowIndex++) {
      final labels = rows[rowIndex].map((cell) => _headerKey(_cellText(cell)));
      final hasName = labels.any((label) =>
          label == 'name' ||
          label == 'firstname' ||
          label == 'fullname' ||
          label == 'customername' ||
          label == 'clientname' ||
          label == 'customname' ||
          label == 'custname');
      final hasPhone = labels.any((label) =>
          label == 'phone' ||
          label == 'phoneno' ||
          label == 'phonenumber' ||
          label == 'mobile' ||
          label == 'mobileno' ||
          label == 'mobilenumber' ||
          label == 'mobilephone' ||
          label == 'contact' ||
          label == 'contactno' ||
          label == 'contactnumber' ||
          label == 'cell' ||
          label == 'cellphone' ||
          label == 'whatsapp' ||
          label == 'number' ||
          label == 'tel' ||
          label == 'telephone');
      if (hasName && hasPhone) return rowIndex;
    }
    return null;
  }

  _CustomerImportColumns _columnsFromHeader(List<xlsx.Data?> headerRow) {
    var columns = const _CustomerImportColumns(
      name: 0,
      phone: 1,
      note: 2,
      referredBy: 3,
    );

    for (var i = 0; i < headerRow.length; i++) {
      final label = _headerKey(_cellText(headerRow[i]));
      if (label == 'name' ||
          label == 'firstname' ||
          label == 'fullname' ||
          label == 'customername' ||
          label == 'clientname' ||
          label == 'customname' ||
          label == 'custname') {
        columns = columns.copyWith(name: i);
      } else if (label == 'phone' ||
          label == 'phoneno' ||
          label == 'phonenumber' ||
          label == 'mobile' ||
          label == 'mobileno' ||
          label == 'mobilenumber' ||
          label == 'mobilephone' ||
          label == 'contact' ||
          label == 'contactno' ||
          label == 'contactnumber' ||
          label == 'cell' ||
          label == 'cellphone' ||
          label == 'whatsapp' ||
          label == 'number' ||
          label == 'tel' ||
          label == 'telephone') {
        columns = columns.copyWith(phone: i);
      } else if (label == 'note' ||
          label == 'notes' ||
          label == 'remark' ||
          label == 'remarks' ||
          label == 'comment' ||
          label == 'comments' ||
          label == 'description') {
        columns = columns.copyWith(note: i);
      } else if (label == 'referredby' ||
          label == 'reference' ||
          label == 'referral' ||
          label == 'refby' ||
          label == 'ref') {
        columns = columns.copyWith(referredBy: i);
      }
    }

    // Safety: if note/referredBy default columns collide with phone,
    // push them to a safe out-of-bounds index so they read as empty.
    final totalCols = headerRow.length;
    final safeEmpty = totalCols + 10; // guaranteed out-of-bounds → empty string
    if (columns.note == columns.phone || columns.note == columns.name) {
      columns = columns.copyWith(note: safeEmpty);
    }
    if (columns.referredBy == columns.phone ||
        columns.referredBy == columns.name) {
      columns = columns.copyWith(referredBy: safeEmpty);
    }

    return columns;
  }

  xlsx.Data? _cellAt(List<xlsx.Data?> row, int column) {
    if (column < 0 || column >= row.length) return null;
    return row[column];
  }

  String _cellText(xlsx.Data? cell) {
    final value = cell?.value;
    return switch (value) {
      null => '',
      xlsx.TextCellValue() => value.value.toString(),
      xlsx.IntCellValue() => value.value.toString(),
      xlsx.DoubleCellValue() => value.value % 1 == 0
          ? value.value.toStringAsFixed(0)
          : value.value.toString(),
      xlsx.BoolCellValue() => value.value.toString(),
      xlsx.DateCellValue() =>
        '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}',
      xlsx.TimeCellValue() =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
      xlsx.DateTimeCellValue() => value.toString(),
      xlsx.FormulaCellValue() => value.formula,
    };
  }

  String _headerKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Returns true if the string looks like a phone number:
  /// at least 7 digits after stripping spaces/dashes/dots.
  bool _looksLikePhone(String value) {
    if (value.isEmpty) return false;
    final digits = value.replaceAll(RegExp(r'[\s\-\(\)\+\.]'), '');
    // Must be mostly digits (at least 7) and not contain letters
    return digits.length >= 7 && RegExp(r'^\d+$').hasMatch(digits);
  }

  String _normalizePhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _editCustomer(Customer customer) async {
    final result = await showDialog<Customer>(
      context: context,
      builder: (context) => _CustomerDialog(customer: customer),
    );
    if (result == null) return;

    await _updateCustomer(customer, result);
  }

  Future<void> _updateCustomer(Customer customer, Customer result) async {
    final index = _customers.indexOf(customer);
    if (index == -1) return;

    final oldName = customer.name;
    setState(() {
      _customers[index] = result;
      for (var i = 0; i < _appointments.length; i++) {
        final appointment = _appointments[i];
        if (appointment.customerName == oldName) {
          _appointments[i] = appointment.copyWith(customerName: result.name);
        }
      }
      for (var i = 0; i < _bills.length; i++) {
        final bill = _bills[i];
        if (bill.customerName == oldName) {
          _bills[i] = Bill(
            bill.id,
            result.name,
            bill.services,
            bill.total,
            bill.date,
            bill.paymentMode,
            bill.servicePrices,
          );
        }
      }
    });
    await _saveState();
  }

  Future<void> _deleteCustomer(Customer customer,
      {bool skipConfirmation = false}) async {
    if (!skipConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Client'),
          content: Text(
            'Delete ${customer.name}? Existing bills and bookings will stay in history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _customers.remove(customer));
    await _saveState();
  }

  /// Clears the notes field for any customer whose notes look like a phone number.
  /// Returns the count of customers that were cleaned.
  Future<int> _cleanPhoneFromNotes() async {
    int cleaned = 0;
    setState(() {
      for (var i = 0; i < _customers.length; i++) {
        final customer = _customers[i];
        if (customer.note.isNotEmpty && _looksLikePhone(customer.note)) {
          _customers[i] = Customer(
            customer.id,
            customer.name,
            customer.phone,
            '', // clear the note
            referredBy: customer.referredBy,
          );
          cleaned++;
        }
      }
    });
    if (cleaned > 0) await _saveState();
    return cleaned;
  }

  Future<void> _addService() async {
    final result = await showDialog<ParlourService>(
      context: context,
      builder: (context) => const _ServiceDialog(),
    );
    if (result == null) return;
    setState(() => _services.add(result));
    await _saveState();
  }

  Future<void> _editService(ParlourService service) async {
    final result = await showDialog<ParlourService>(
      context: context,
      builder: (context) => _ServiceDialog(service: service),
    );
    if (result == null) return;

    final index = _services.indexOf(service);
    if (index == -1) return;

    setState(() => _services[index] = result);
    await _saveState();
  }

  Future<void> _deleteService(ParlourService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Service'),
        content: Text('Delete ${service.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _services.remove(service));
    await _saveState();
  }

  Future<void> _addPurchase() async {
    final result = await showDialog<List<PurchaseItem>>(
      context: context,
      builder: (context) =>
          _PurchaseDialog(invoiceId: _nextPurchaseInvoiceId()),
    );
    if (result == null || result.isEmpty) return;

    setState(() => _purchases.addAll(result));
    await _saveState();
  }

  String _nextPurchaseInvoiceId() {
    final usedIds = _purchases.map((purchase) => purchase.invoiceId).toSet();
    var highest = 0;
    for (final purchase in _purchases) {
      final match = RegExp(r'^PI-(\d+)$').firstMatch(purchase.invoiceId);
      if (match == null) continue;
      final number = int.tryParse(match.group(1)!);
      if (number != null && number > highest) highest = number;
    }

    var next = highest + 1;
    var invoiceId = 'PI-${next.toString().padLeft(3, '0')}';
    while (usedIds.contains(invoiceId)) {
      next++;
      invoiceId = 'PI-${next.toString().padLeft(3, '0')}';
    }
    return invoiceId;
  }

  Future<void> _editPurchase(PurchaseItem purchase) async {
    final result = await showDialog<List<PurchaseItem>>(
      context: context,
      builder: (context) => _PurchaseDialog(purchase: purchase),
    );
    if (result == null || result.isEmpty) return;

    final index = _purchases.indexOf(purchase);
    if (index == -1) return;

    setState(() => _purchases[index] = result.first);
    await _saveState();
  }

  Future<void> _deletePurchase(PurchaseItem purchase) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Purchase'),
        content: Text('Delete ${purchase.itemName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _purchases.remove(purchase));
    await _saveState();
  }

  Future<void> _addInvestment() async {
    final result = await showDialog<InvestmentTransaction>(
      context: context,
      builder: (context) => const _InvestmentDialog(),
    );
    if (result == null) return;

    setState(() => _investments.add(result));
    await _saveState();
  }

  Future<void> _editInvestment(InvestmentTransaction item) async {
    final result = await showDialog<InvestmentTransaction>(
      context: context,
      builder: (context) => _InvestmentDialog(transaction: item),
    );
    if (result == null) return;

    final index = _investments.indexOf(item);
    if (index == -1) return;

    setState(() => _investments[index] = result);
    await _saveState();
  }

  Future<void> _deleteInvestment(InvestmentTransaction item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: Text('Delete "${item.title}" (${money(item.amount)})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _investments.remove(item));
    await _saveState();
  }

  Future<void> _addAppointment({DateTime? initialDate}) async {
    final result = await showDialog<Appointment>(
      context: context,
      builder: (context) => _AppointmentDialog(
        customers: _customers,
        services: _services,
        initialDate: initialDate,
      ),
    );
    if (result == null) return;

    setState(() => _appointments.add(result));
    await _saveState();

    final customer = _customers.firstWhere((c) => c.name == result.customerName,
        orElse: () => const Customer('', '', '', ''));
    await scheduleAppointmentNotification(
      result,
      customer.phone,
      enabled: _bookingReminderEnabled,
      reminderMinutes: _reminderMinutes,
    );
    unawaited(scheduleDailySummaryNotification(_appointments));

    // Auto-send WhatsApp poll if customer has a phone number
    if (_hasGreenApiSettings && customer.phone.trim().isNotEmpty) {
      await _sendGreenApiConfirmationPoll(result, customer.phone.trim());
    } else if (customer.phone.trim().isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number — WhatsApp poll not sent'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _addConfirmedOnlineBooking({
    required String customerName,
    required String customerPhone,
    required String serviceName,
    required DateTime date,
    required TimeOfDay time,
    required double amount,
  }) async {
    final existingIndex = _customers.indexWhere(
      (c) =>
          c.name.toLowerCase() == customerName.toLowerCase() ||
          (customerPhone.isNotEmpty && c.phone == customerPhone),
    );
    if (existingIndex == -1 && customerName.isNotEmpty) {
      final newCust =
          Customer(customerName, customerPhone, '', 'Online Booking');
      setState(() => _customers.add(newCust));
    }

    final appointment = Appointment(
      customerName,
      serviceName,
      date,
      time,
      'Confirmed',
    );

    setState(() => _appointments.add(appointment));
    await _saveState();

    await scheduleAppointmentNotification(
      appointment,
      customerPhone,
      enabled: _bookingReminderEnabled,
      reminderMinutes: _reminderMinutes,
    );
    unawaited(scheduleDailySummaryNotification(_appointments));
  }

  Future<void> _openOnlineBookingsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OnlineBookingsScreen(
          parlourName: _parlourName,
          shopPhone: _shopPhone,
          shopAddress: _shopAddress,
          existingAppointments: _appointments.map((a) {
            final hour = a.time.hourOfPeriod == 0 ? 12 : a.time.hourOfPeriod;
            final minute = a.time.minute.toString().padLeft(2, '0');
            final period = a.time.period == DayPeriod.am ? 'AM' : 'PM';
            final slot = '${hour.toString().padLeft(2, '0')}:$minute $period';
            return {
              'customerName': a.customerName,
              'serviceName': a.serviceName,
              'date': a.date,
              'timeSlot': slot,
              'status': a.status,
            };
          }).toList(),
          onAddConfirmedAppointment: _addConfirmedOnlineBooking,
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _editAppointment(Appointment appointment) async {
    final result = await showDialog<Appointment>(
      context: context,
      builder: (context) => _AppointmentDialog(
          customers: _customers, services: _services, appointment: appointment),
    );
    if (result == null) return;

    final index = _appointments.indexOf(appointment);
    if (index == -1) return;

    setState(() => _appointments[index] = result);
    await _saveState();

    await cancelAppointmentNotification(appointment);
    final customer = _customers.firstWhere((c) => c.name == result.customerName,
        orElse: () => const Customer('', '', '', ''));
    await scheduleAppointmentNotification(
      result,
      customer.phone,
      enabled: _bookingReminderEnabled,
      reminderMinutes: _reminderMinutes,
    );
    unawaited(scheduleDailySummaryNotification(_appointments));
    if (result.status == 'Pending') {
      await _sendAppointmentConfirmationMessage(result);
    }
  }

  Future<void> _confirmAppointment(Appointment appointment) async {
    final index = _appointments.indexOf(appointment);
    if (index == -1) return;

    final updated = appointment.copyWith(status: 'Confirmed');

    setState(() => _appointments[index] = updated);
    await _saveState();
  }

  Future<void> _markAppointmentArrived(Appointment appointment) async {
    final index = _appointments.indexOf(appointment);
    if (index == -1) return;

    final updated = appointment.copyWith(status: 'Arrived');

    setState(() => _appointments[index] = updated);
    await _saveState();
    await cancelAppointmentNotification(appointment);
  }

  Future<void> _sendAppointmentConfirmationMessage(
      Appointment appointment) async {
    final customer = _customers.firstWhere(
      (c) => c.name == appointment.customerName,
      orElse: () => const Customer('', '', '', ''),
    );
    final phone = customer.phone.trim();
    if (phone.isEmpty) return;

    // Auto-send poll if Green API is configured — no confirmation dialog needed
    if (!_hasGreenApiSettings) return;

    await _sendGreenApiConfirmationPoll(appointment, phone);
  }

  bool get _hasGreenApiSettings =>
      _greenApiUrl.trim().isNotEmpty &&
      _greenApiInstanceId.trim().isNotEmpty &&
      _greenApiToken.trim().isNotEmpty;

  Future<void> _sendGreenApiConfirmationPoll(
    Appointment appointment,
    String phone,
  ) async {
    final normalizedPhone = _normalizePhoneForWhatsApp(phone);
    final apiUrl = _greenApiUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$apiUrl/waInstance${_greenApiInstanceId.trim()}/sendPoll/${_greenApiToken.trim()}',
    );
    final date =
        '${appointment.date.day.toString().padLeft(2, '0')}/${appointment.date.month.toString().padLeft(2, '0')}/${appointment.date.year}';

    try {
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chatId': '$normalizedPhone@c.us',
          'message':
              'Confirm your booking: ${appointment.serviceName} on $date at ${appointment.time.format(context)}',
          'options': [
            {'optionName': '✅ Yes, I confirm'},
            {'optionName': '❌ No, cancel'},
          ],
          'multipleAnswers': false,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final idMessage = decoded['idMessage'] as String?;
        if (idMessage != null && idMessage.isNotEmpty) {
          await _setAppointmentPollId(appointment, idMessage);
          await _configureGreenApiNotifications();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ WhatsApp poll sent'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      if (mounted) {
        final body = response.body.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              body.isEmpty
                  ? 'Poll failed: HTTP ${response.statusCode}'
                  : 'Poll failed: $body',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Poll failed. Check internet and Green API details.'),
          ),
        );
      }
    }
  }

  Future<void> _setAppointmentPollId(
    Appointment appointment,
    String pollId,
  ) async {
    final index = _appointments.indexWhere(
      (item) =>
          item.customerName == appointment.customerName &&
          item.serviceName == appointment.serviceName &&
          item.date.year == appointment.date.year &&
          item.date.month == appointment.date.month &&
          item.date.day == appointment.date.day &&
          item.time.hour == appointment.time.hour &&
          item.time.minute == appointment.time.minute,
    );
    if (index == -1) return;

    setState(() {
      _appointments[index] =
          _appointments[index].copyWith(confirmationPollId: pollId);
    });
    await _saveState();
  }

  Future<void> _configureGreenApiNotifications() async {
    if (!_hasGreenApiSettings) return;

    final apiUrl = _greenApiUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$apiUrl/waInstance${_greenApiInstanceId.trim()}/setSettings/${_greenApiToken.trim()}',
    );

    try {
      await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'webhookUrl': '',
          'incomingWebhook': 'yes',
          'outgoingAPIMessageWebhook': 'yes',
          'outgoingMessageWebhook': 'yes',
          'pollMessageWebhook': 'yes',
        }),
      );
    } catch (_) {
      // Poll sending can still work; notification setup errors are shown via poll status checks.
    }
  }

  Future<void> _checkGreenApiNotifications() async {
    if (!_hasGreenApiSettings || _checkingGreenApiNotifications) return;
    _checkingGreenApiNotifications = true;

    try {
      for (var i = 0; i < 5; i++) {
        final notification = await _receiveGreenApiNotification();
        if (notification == null) break;

        final receiptId = notification['receiptId'];
        final body = notification['body'];
        if (body is Map<String, dynamic>) {
          await _handleGreenApiNotificationBody(body);
        }
        if (receiptId != null) {
          await _deleteGreenApiNotification(receiptId);
        }
      }
    } finally {
      _checkingGreenApiNotifications = false;
    }
  }

  Future<Map<String, dynamic>?> _receiveGreenApiNotification() async {
    final apiUrl = _greenApiUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$apiUrl/waInstance${_greenApiInstanceId.trim()}/receiveNotification/${_greenApiToken.trim()}',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _deleteGreenApiNotification(Object receiptId) async {
    final apiUrl = _greenApiUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$apiUrl/waInstance${_greenApiInstanceId.trim()}/deleteNotification/${_greenApiToken.trim()}/$receiptId',
    );

    try {
      await http.delete(uri);
    } catch (_) {}
  }

  Future<void> _handleGreenApiNotificationBody(
    Map<String, dynamic> body,
  ) async {
    // Deep-search the notification for any poll vote data
    // Green API can nest it differently across versions
    final String raw = jsonEncode(body);

    // Must contain poll-related keywords
    if (!raw.contains('poll') && !raw.contains('Poll')) return;

    // Extract votes from anywhere in the structure
    Map<String, dynamic>? pollData;
    final messageData = body['messageData'];
    if (messageData is Map<String, dynamic>) {
      pollData = messageData['pollMessageData'] as Map<String, dynamic>?;
    }
    pollData ??= body['pollMessageData'] as Map<String, dynamic>?;
    if (pollData == null) return;

    final votes = pollData['votes'];
    if (votes is! List || votes.isEmpty) return;

    var selectedStatus = '';
    for (final vote in votes.whereType<Map>()) {
      final optionName = '${vote['optionName']}'.trim().toLowerCase();
      final voters = vote['optionVoters'];
      final hasVoters = voters is List && voters.isNotEmpty;
      if (!hasVoters) continue;

      if (optionName.contains('yes') || optionName.contains('confirm')) {
        selectedStatus = 'Confirmed';
        break;
      } else if (optionName.contains('no') || optionName.contains('cancel')) {
        selectedStatus = 'Cancelled';
        break;
      }
    }

    if (selectedStatus.isEmpty) return;

    // Try to match by stored poll ID first
    final pollId = (pollData['stanzaId'] ??
        pollData['pollMessageId'] ??
        body['idMessage']) as String?;

    var index = pollId != null
        ? _appointments.indexWhere((a) => a.confirmationPollId == pollId)
        : -1;

    // Fallback: update the most recent Pending appointment
    if (index == -1) {
      index = _appointments.lastIndexWhere((a) => a.status == 'Pending');
    }

    if (index == -1) return;

    setState(() {
      _appointments[index] =
          _appointments[index].copyWith(status: selectedStatus);
    });
    await _saveState();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            selectedStatus == 'Confirmed' ? Colors.green : Colors.red,
        content: Text(
          '${_appointments[index].customerName} booking $selectedStatus via WhatsApp',
        ),
      ),
    );
  }

  String _normalizePhoneForWhatsApp(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '91$digits';
    return digits;
  }

  Future<void> _deleteAppointment(Appointment appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Booking'),
        content: Text(
          'Delete ${appointment.customerName} - ${appointment.serviceName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _appointments.remove(appointment));
    await _saveState();
    await cancelAppointmentNotification(appointment);
    unawaited(scheduleDailySummaryNotification(_appointments));
  }

  Future<void> _addBill({Customer? forCustomer}) async {
    final result = await showDialog<Bill>(
      context: context,
      builder: (context) => _BillDialog(
        customers: _customers,
        services: _services,
        initialCustomer: forCustomer,
        invoiceId: _nextInvoiceId(),
      ),
    );
    if (result == null) return;
    setState(() {
      _ensureCustomerForName(result.customerName);
      _bills.add(result);
    });
    await _saveState();
  }

  String _nextInvoiceId() {
    final usedIds = _bills.map((bill) => bill.id).toSet();
    var highest = 0;
    for (final bill in _bills) {
      final id = bill.id.trim();
      if (RegExp(r'^\d+$').hasMatch(id)) {
        final number = int.tryParse(id);
        if (number != null && number > highest) highest = number;
      }
    }

    var next = highest + 1;
    var invoiceId = next.toString().padLeft(3, '0');
    while (usedIds.contains(invoiceId)) {
      next++;
      invoiceId = next.toString().padLeft(3, '0');
    }
    return invoiceId;
  }

  Future<void> _editBill(Bill bill) async {
    final result = await showDialog<Bill>(
      context: context,
      builder: (context) =>
          _BillDialog(customers: _customers, services: _services, bill: bill),
    );
    if (result == null) return;

    final index = _bills.indexOf(bill);
    if (index == -1) return;

    setState(() {
      _ensureCustomerForName(result.customerName);
      _bills[index] = result;
    });
    await _saveState();
  }

  Future<void> _deleteBill(Bill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text('Delete bill ${bill.id} for ${bill.customerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _bills.remove(bill));
    await _saveState();
  }

  void _ensureCustomerForName(String name) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return;

    final exists = _customers.any(
      (customer) =>
          customer.name.trim().toLowerCase() == normalizedName.toLowerCase(),
    );
    if (exists) return;

    _customers.add(Customer(
      'C-${DateTime.now().microsecondsSinceEpoch}',
      normalizedName,
      '',
      '',
    ));
  }

  void _reconcileCustomersFromActivity() {
    final names = <String>{
      for (final bill in _bills) bill.customerName,
      for (final appointment in _appointments) appointment.customerName,
    };
    for (final name in names) {
      _ensureCustomerForName(name);
    }
  }

  Future<void> _loadSavedState() async {
    var raw = await _localStore.loadStateJson();
    if (raw == null || raw.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        await _localStore.saveStateJson(raw);
      }
    }

    if (raw == null || raw.isEmpty) {
      setState(() {
        _mergeSeedCustomers();
      });
      await _saveState();
      return;
    }

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      _applyBackupData(data);
      var addedSeedCustomers = 0;
      setState(() {
        addedSeedCustomers = _mergeSeedCustomers();
      });
      if (addedSeedCustomers > 0) {
        await _saveState();
      }
      if (!_hasBusinessData(data) && addedSeedCustomers == 0) {
        _scheduleFirstRunRestorePrompt();
      }
      unawaited(_tryScheduledDailyGoogleBackup());
      unawaited(scheduleDailySummaryNotification(_appointments));
    } catch (_) {
      // Keep default data if an older/corrupt saved payload is found.
      setState(() {
        _mergeSeedCustomers();
      });
      await _saveState();
    }
  }

  Future<void> _saveState() async {
    await _localStore.saveStateJson(jsonEncode(_backupPayload()));
    await _requestAndroidBackup();
    unawaited(_tryAutoGoogleBackup());
  }

  int _mergeSeedCustomers() {
    final existingPhones = _customers
        .map((customer) => _normalizePhone(customer.phone))
        .where((phone) => phone.isNotEmpty)
        .toSet();
    final existingNamePhone = _customers
        .map((customer) =>
            '${customer.name.trim().toLowerCase()}|${_normalizePhone(customer.phone)}')
        .toSet();
    var added = 0;

    for (final seed in seedCustomerContacts) {
      final phone = _normalizePhone(seed.phone);
      final namePhone = '${seed.name.trim().toLowerCase()}|$phone';
      final isDuplicate = phone.isNotEmpty
          ? existingPhones.contains(phone)
          : existingNamePhone.contains(namePhone);
      if (isDuplicate) continue;

      _customers.add(Customer(seed.id, seed.name, seed.phone, ''));
      existingPhones.add(phone);
      existingNamePhone.add(namePhone);
      added++;
    }

    return added;
  }

  Future<void> _requestAndroidBackup() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _backupChannel.invokeMethod<void>('dataChanged');
    } catch (_) {
      // Backup is best-effort. Local persistence still works without it.
    }
  }

  Future<String> _backupToGoogleDrive() async {
    if (!_isGoogleDriveConfigured) {
      return 'Local phone data is already saving automatically.';
    }

    final account = await _uploadBackupToDrive(interactive: true);
    if (account != null) {
      await _markDailyGoogleBackupDone();
    }
    return 'Backup saved to ${account ?? 'Google Drive'}';
  }

  Future<String> _connectGmailForBackup() async {
    if (!_isGoogleDriveConfigured) {
      return 'Google login is not configured yet. Local phone data is still saving on this device.';
    }

    final account = await _uploadBackupToDrive(interactive: true);
    if (account != null) {
      await _markDailyGoogleBackupDone();
    }
    return 'Gmail connected and backup saved to ${account ?? 'Google Drive'}.';
  }

  Future<String> _restoreFromGoogleDrive() async {
    if (!_isGoogleDriveConfigured) {
      return 'Google Drive restore is not set up. Local phone data is still available.';
    }

    final data = await _downloadBackupFromDrive(interactive: true);
    if (!mounted) return 'Backup restored';

    _applyBackupData(data);
    await _saveState();
    final account = await _savedBackupAccount();
    return 'Backup restored from ${account ?? 'Google Drive'}';
  }

  Future<String> _shareLocalBackup() async {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'nupur_beauty_parlour_backup_$timestamp.json';
    final bytes = utf8.encode(jsonEncode(_backupPayload()));

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'application/json',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
        subject: 'Nupur Beauty Parlour data backup',
        text:
            'Backup for $_backupEmail. Restore this file inside the Nupur Beauty Parlour app.',
      ),
    );

    return 'Backup file is ready to share.';
  }

  Future<String> _importLocalBackup() async {
    const backupType = XTypeGroup(
      label: 'Nupur Beauty Parlour backup',
      extensions: ['json'],
      mimeTypes: ['application/json'],
    );

    final file = await openFile(acceptedTypeGroups: [backupType]);
    if (file == null) {
      return 'Import cancelled.';
    }

    final decoded = jsonDecode(utf8.decode(await file.readAsBytes()));
    if (decoded is! Map) {
      throw StateError('This is not a valid app backup file.');
    }

    _applyBackupData(Map<String, dynamic>.from(decoded));
    await _saveState();
    return 'Backup imported on this phone.';
  }

  void _applyBackupData(Map<String, dynamic> data) {
    final customers = (data['customers'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Customer.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final services = (data['services'] as List? ?? [])
        .whereType<Map>()
        .map((item) => ParlourService.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final appointments = (data['appointments'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Appointment.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final bills = (data['bills'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Bill.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final purchases = (data['purchases'] as List? ?? [])
        .whereType<Map>()
        .map((item) => PurchaseItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final investments = (data['investments'] as List? ?? [])
        .whereType<Map>()
        .map((item) =>
            InvestmentTransaction.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    setState(() {
      _customers
        ..clear()
        ..addAll(customers);
      if (services.isNotEmpty) {
        _services
          ..clear()
          ..addAll(services);
      }
      _appointments
        ..clear()
        ..addAll(appointments);
      _bills
        ..clear()
        ..addAll(bills);
      _purchases
        ..clear()
        ..addAll(purchases);
      _investments
        ..clear()
        ..addAll(investments);
      _reconcileCustomersFromActivity();
      final settings = data['settings'] is Map
          ? _ShopSettings.fromJson(
              Map<String, dynamic>.from(data['settings'] as Map),
              _shopSettings,
            )
          : _ShopSettings.fromJson(data, _shopSettings);
      _applyShopSettings(settings);
    });
  }

  bool _hasBusinessData(Map<String, dynamic> data) {
    final customers = data['customers'] as List?;
    final appointments = data['appointments'] as List?;
    final bills = data['bills'] as List?;
    final purchases = data['purchases'] as List?;
    final investments = data['investments'] as List?;
    return (customers?.isNotEmpty ?? false) ||
        (appointments?.isNotEmpty ?? false) ||
        (bills?.isNotEmpty ?? false) ||
        (purchases?.isNotEmpty ?? false) ||
        (investments?.isNotEmpty ?? false);
  }

  void _scheduleFirstRunRestorePrompt() {
    // Google sign-in should only open after the user taps a backup/restore
    // button. Some Android devices keep re-opening the account chooser when an
    // automatic first-run prompt starts the flow.
  }

  Future<void> _showFirstRunRestorePrompt() async {
    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore previous data?'),
        content: Text(
          'Sign in with $_backupEmail to restore your customers, appointments, bills, services, and settings from Google Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.login_outlined),
            label: const Text('Login & Restore'),
          ),
        ],
      ),
    );

    if (shouldRestore != true || !mounted) return;
    try {
      final message = await _restoreFromGoogleDrive();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      final message = _friendlyBackupError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  String _friendlyBackupError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (message.contains('GoogleSignInExceptionCode.canceled') ||
        message.contains('Account reauth failed')) {
      return 'Google login was cancelled or expired. Tap Backup to Google Drive again, choose the backup Gmail, and allow Drive permission.';
    }
    if (message.contains('clientConfigurationError') ||
        message.contains('providerConfigurationError') ||
        message.contains('ApiException: 10')) {
      return 'Google backup is not configured correctly. Rebuild the APK with the correct Google Web Client ID and Android SHA-1 setup.';
    }
    return message;
  }

  Future<void> _tryAutoGoogleBackup() async {
    if (!_isGoogleDriveConfigured) return;
    if (!_autoBackupEnabled) return;
    if (await _savedBackupAccount() == null) return;

    try {
      final account = await _uploadBackupToDrive(interactive: false);
      if (account != null) {
        await _markDailyGoogleBackupDone();
      }
    } catch (_) {
      // User can still use Backup Now from Settings.
    }
  }

  Future<void> _tryScheduledDailyGoogleBackup() async {
    if (!_isGoogleDriveConfigured) return;
    if (!_autoBackupEnabled) return;
    if (await _savedBackupAccount() == null) return;
    if (!_hasAnyLocalBusinessData) return;

    final prefs = await SharedPreferences.getInstance();
    final today = _backupDateStamp(DateTime.now());
    if (prefs.getString(_dailyBackupDateKey) == today) return;

    try {
      final account = await _uploadBackupToDrive(interactive: false);
      if (account != null) {
        await prefs.setString(_dailyBackupDateKey, today);
      }
    } catch (_) {
      // Daily backup will be retried next time the app opens or resumes.
    }
  }

  Future<void> _markDailyGoogleBackupDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _dailyBackupDateKey, _backupDateStamp(DateTime.now()));
  }

  String _backupDateStamp(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  bool get _hasAnyLocalBusinessData =>
      _customers.isNotEmpty ||
      _appointments.isNotEmpty ||
      _bills.isNotEmpty ||
      _purchases.isNotEmpty;

  Future<String?> _uploadBackupToDrive({required bool interactive}) async {
    final session = await _driveSession(interactive: interactive);
    if (session == null) return null;

    final bytes = utf8.encode(jsonEncode(_backupPayload()));
    final existing = await _findDriveBackup(session.driveApi);
    final media = drive.Media(
      Stream<List<int>>.value(bytes),
      bytes.length,
      contentType: 'application/json',
    );

    if (existing?.id == null) {
      await session.driveApi.files.create(
        drive.File()
          ..name = _driveBackupFileName
          ..parents = ['appDataFolder'],
        uploadMedia: media,
        uploadOptions: drive.UploadOptions.defaultOptions,
        $fields: 'id,name',
      );
    } else {
      await session.driveApi.files.update(
        drive.File()..name = _driveBackupFileName,
        existing!.id!,
        uploadMedia: media,
        uploadOptions: drive.UploadOptions.defaultOptions,
        $fields: 'id,name',
      );
    }

    return session.email;
  }

  Future<Map<String, dynamic>> _downloadBackupFromDrive({
    required bool interactive,
  }) async {
    final session = await _driveSession(interactive: interactive);
    if (session == null) {
      throw StateError('Please sign in with your backup Gmail first.');
    }

    final backup = await _findDriveBackup(session.driveApi);
    if (backup?.id == null) {
      throw StateError('No Google Drive backup found for ${session.email}.');
    }

    final response = await session.driveApi.files.get(
      backup!.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    final media = response as drive.Media;
    final bytes = await media.stream.expand((chunk) => chunk).toList();
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Map<String, dynamic> _backupPayload() {
    return {
      'updatedAt': DateTime.now().toIso8601String(),
      'parlourName': _parlourName,
      'ownerName': _ownerName,
      'settings': _shopSettings.toJson(),
      'customers': _customers.map((customer) => customer.toJson()).toList(),
      'services': _services.map((service) => service.toJson()).toList(),
      'appointments':
          _appointments.map((appointment) => appointment.toJson()).toList(),
      'bills': _bills.map((bill) => bill.toJson()).toList(),
      'purchases': _purchases.map((purchase) => purchase.toJson()).toList(),
      'investments':
          _investments.map((investment) => investment.toJson()).toList(),
    };
  }

  Future<_DriveSession?> _driveSession({required bool interactive}) async {
    if (!_isGoogleDriveConfigured) {
      throw StateError(
        'Google Drive backup is not configured yet. App data will still save on this phone.',
      );
    }

    GoogleSignInAccount? account;

    if (interactive) {
      account =
          await GoogleSignIn.instance.authenticate(scopeHint: _driveScopes);
    } else {
      final lightweight =
          GoogleSignIn.instance.attemptLightweightAuthentication();
      account = lightweight == null ? null : await lightweight;
    }

    if (account == null) return null;
    if (account.email.toLowerCase() != _backupEmail.toLowerCase()) {
      if (!interactive) return null;
      throw StateError(
        'Please select $_backupEmail for app backup and restore.',
      );
    }
    final savedEmail = await _savedBackupAccount();
    if (savedEmail != null &&
        savedEmail.toLowerCase() != account.email.toLowerCase()) {
      if (!interactive) return null;
    }
    final headers = interactive
        ? await _interactiveDriveAuthorizationHeaders(account)
        : await account.authorizationClient.authorizationHeaders(_driveScopes);
    if (headers == null) {
      if (!interactive) return null;
      throw StateError('Google Drive permission was not granted.');
    }

    if (interactive) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_backupAccountKey, account.email);
    }

    return _DriveSession(
      email: account.email,
      driveApi: drive.DriveApi(_GoogleAuthClient(headers)),
    );
  }

  Future<Map<String, String>?> _interactiveDriveAuthorizationHeaders(
    GoogleSignInAccount account,
  ) async {
    final authorizationClient = account.authorizationClient;
    final authorization =
        await authorizationClient.authorizationForScopes(_driveScopes) ??
            await authorizationClient.authorizeScopes(_driveScopes);

    return <String, String>{
      'Authorization': 'Bearer ${authorization.accessToken}',
      'X-Goog-AuthUser': '0',
    };
  }

  Future<String?> _savedBackupAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_backupAccountKey);
  }

  bool get _isGoogleDriveConfigured =>
      !kIsWeb && _googleSignInServerClientId.isNotEmpty;

  Future<drive.File?> _findDriveBackup(drive.DriveApi driveApi) async {
    final escapedName = _driveBackupFileName.replaceAll("'", r"\'");
    final result = await driveApi.files.list(
      spaces: 'appDataFolder',
      q: "name = '$escapedName' and trashed = false",
      pageSize: 1,
      $fields: 'files(id,name,modifiedTime)',
    );
    final files = result.files ?? const <drive.File>[];
    return files.isEmpty ? null : files.first;
  }

  Future<void> _exportBillPdf(Bill bill) async {
    final bytes = await _buildBillPdf(bill);
    final fileName =
        '${bill.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';

    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName,
    );
  }

  Future<void> _shareBillPdfToClientWhatsApp(Bill bill) async {
    final customer = _customers.firstWhere(
      (customer) => customer.name == bill.customerName,
      orElse: () => const Customer('', '', '', ''),
    );
    final phone = _whatsAppPhone(customer.phone);

    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Client phone number not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final bytes = await _buildBillPdf(bill);
    final fileName =
        '${bill.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
      return;
    }

    try {
      await _shareChannel.invokeMethod<void>('sharePdfToWhatsApp', {
        'bytes': bytes,
        'fileName': fileName,
        'phone': phone,
        'title': 'Bill ${bill.id}',
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Could not open WhatsApp'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Uint8List> _buildBillPdf(Bill bill) async {
    final date =
        '${bill.date.day.toString().padLeft(2, '0')}/${bill.date.month.toString().padLeft(2, '0')}/${bill.date.year}';
    final fallbackPrice =
        bill.services.isEmpty ? 0.0 : bill.total / bill.services.length;
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _parlourName,
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              if (_shopPhone.trim().isNotEmpty)
                pw.Text(
                  'Phone: ${_shopPhone.trim()}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              if (_shopAddress.trim().isNotEmpty)
                pw.Text(
                  _shopAddress.trim(),
                  style: const pw.TextStyle(fontSize: 11),
                ),
              if (_shopPhone.trim().isNotEmpty ||
                  _shopAddress.trim().isNotEmpty)
                pw.SizedBox(height: 6),
              pw.Text('Bill Receipt', style: const pw.TextStyle(fontSize: 14)),
              pw.Divider(height: 28),
              _pdfInfoRow('Bill No.', bill.id),
              _pdfInfoRow('Customer', bill.customerName),
              _pdfInfoRow('Date', date),
              _pdfInfoRow('Payment', bill.paymentMode.label),
              pw.SizedBox(height: 18),
              pw.Text(
                'Services',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              if (bill.services.isEmpty)
                pw.Text(
                  'No services',
                  style: const pw.TextStyle(fontSize: 12),
                )
              else
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(),
                    1: pw.FixedColumnWidth(90),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(width: 0.5),
                        ),
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 6),
                          child: pw.Text(
                            'Service',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 6),
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(
                              'Price',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    ...bill.services.map((service) {
                      final price =
                          bill.servicePrices[service] ?? fallbackPrice;
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 6),
                            child: pw.Text(
                              service,
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 6),
                            child: pw.Align(
                              alignment: pw.Alignment.centerRight,
                              child: pw.Text(
                                money(price),
                                style: const pw.TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              pw.Divider(height: 28),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Total',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    money(bill.total),
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Center(
                child: pw.Text(
                  _invoiceFooter.trim().isEmpty
                      ? 'Thank you.'
                      : _invoiceFooter.trim(),
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  String _whatsAppPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '91$digits';
    return digits;
  }
}

class _DashboardPage extends StatefulWidget {
  const _DashboardPage({
    required this.parlourName,
    required this.appointments,
    required this.bills,
    required this.purchases,
    required this.investments,
    required this.customers,
    required this.onQuickAction,
    required this.onOpenTab,
    required this.onShareBackup,
    required this.onImportBackup,
  });

  final String parlourName;
  final List<Appointment> appointments;
  final List<Bill> bills;
  final List<PurchaseItem> purchases;
  final List<InvestmentTransaction> investments;
  final List<Customer> customers;
  final ValueChanged<String> onQuickAction;
  final ValueChanged<int> onOpenTab;
  final VoidCallback onShareBackup;
  final VoidCallback onImportBackup;

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  late DateTime _rangeStart;
  late DateTime _rangeEnd;

  @override
  void initState() {
    super.initState();
    _rangeStart = DateTime(2000, 1, 1);
    _rangeEnd = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final filteredBills = widget.bills
        .where((bill) => _isDateInRange(bill.date, _rangeStart, _rangeEnd))
        .toList();
    final filteredAppointments = widget.appointments
        .where((appointment) =>
            _isDateInRange(appointment.date, _rangeStart, _rangeEnd))
        .toList()
      ..sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        final aMinutes = a.time.hour * 60 + a.time.minute;
        final bMinutes = b.time.hour * 60 + b.time.minute;
        return aMinutes.compareTo(bMinutes);
      });
    final filteredPurchases = widget.purchases
        .where((purchase) =>
            _isDateInRange(purchase.dateTime, _rangeStart, _rangeEnd))
        .toList();
    final filteredInvestments = widget.investments
        .where((inv) =>
            _isDateInRange(inv.dateTime, _rangeStart, _rangeEnd))
        .toList();
    final rangeCollection =
        filteredBills.fold<double>(0, (total, bill) => total + bill.total);
    final rangePurchases = filteredPurchases.fold<double>(
        0, (total, purchase) => total + purchase.total);
    final totalCredit = filteredInvestments
        .where((e) => e.type == InvestmentType.credit)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final totalDebit = filteredInvestments
        .where((e) => e.type == InvestmentType.debit)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final netInvestment = totalCredit - totalDebit;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: _Header(
                    title: widget.parlourName,
                    subtitle: 'Only for ladies - ready for a great day?')),
            CircleAvatar(
              radius: 26,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
              child: Icon(Icons.spa_rounded,
                  color: Theme.of(context).colorScheme.primary, size: 28),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _DashboardDateRangeFilter(
          start: _rangeStart,
          end: _rangeEnd,
          onTap: _pickDateRange,
        ),
        const SizedBox(height: 30),
        _MetricGrid(
          metrics: [
            _Metric('Sales', money(rangeCollection), Icons.payments_rounded,
                const Color(0xff059669),
                onTap: () => widget.onOpenTab(7)),
            _Metric('Bookings', filteredAppointments.length.toString(),
                Icons.event_available_rounded, const Color(0xff2563EB),
                onTap: () => widget.onOpenTab(2)),
            _Metric('Balance', money(rangeCollection - rangePurchases),
                Icons.account_balance_wallet_rounded,
                (rangeCollection - rangePurchases) >= 0
                    ? const Color(0xff059669)
                    : const Color(0xffDC2626)),
            _Metric('Purchases', money(rangePurchases),
                Icons.shopping_bag_rounded, const Color(0xff0369A1),
                onTap: () => widget.onOpenTab(5)),
          ],
        ),
        const SizedBox(height: 16),
        Material(
          color: _cardColor(context),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => widget.onOpenTab(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xff0EA5E9).withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xff0EA5E9).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xff0EA5E9),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invest Balance',
                          style: TextStyle(
                            color: _mutedTextColor(context),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          money(netInvestment),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: netInvestment >= 0
                                ? const Color(0xff059669)
                                : const Color(0xffDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xff0EA5E9).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View',
                          style: TextStyle(
                            color: Color(0xff0EA5E9),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          color: Color(0xff0EA5E9),
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        const _SectionTitle('Quick Actions'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: _ActionButton(
                    icon: Icons.person_add_rounded,
                    label: 'Client',
                    color: const Color(0xff10B981),
                    onTap: () => widget.onQuickAction('customer'))),
            const SizedBox(width: 12),
            Expanded(
                child: _ActionButton(
                    icon: Icons.calendar_month_rounded,
                    label: 'Booking',
                    color: const Color(0xff6366F1),
                    onTap: () => widget.onQuickAction('appointment'))),
            const SizedBox(width: 12),
            Expanded(
                child: _ActionButton(
                    icon: Icons.receipt_long_rounded,
                    label: 'Bill',
                    color: const Color(0xffF59E0B),
                    onTap: () => widget.onQuickAction('bill'))),
          ],
        ),
        const SizedBox(height: 32),
        const _SectionTitle('Data Backup'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.share_rounded,
                label: 'Share Backup',
                color: const Color(0xff0EA5E9),
                onTap: widget.onShareBackup,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.file_download_rounded,
                label: 'Import Backup',
                color: const Color(0xff8B5CF6),
                onTap: widget.onImportBackup,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const _SectionTitle('Schedule'),
        const SizedBox(height: 16),
        ...filteredAppointments
            .map((appointment) => _AppointmentTile(appointment: appointment)),
        if (filteredAppointments.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: _cardColor(context),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: _softShadowColor(context),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]),
            child: Center(
                child: Text("No bookings yet",
                    style: TextStyle(color: _mutedTextColor(context)))),
          ),
        const SizedBox(height: 32),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    // Find the earliest date across all data entries
    final allDates = [
      ...widget.bills.map((b) => b.date),
      ...widget.purchases.map((p) => p.dateTime),
      ...widget.appointments.map((a) => a.date),
    ];
    final earliest = allDates.isEmpty
        ? null
        : allDates.reduce((a, b) => a.isBefore(b) ? a : b);

    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => _BookingDateRangeDialog(
        initialStart: _rangeStart,
        initialEnd: _rangeEnd,
        initialPreset: 'All Time',
        earliestDate: earliest != null
            ? DateTime(earliest.year, earliest.month, earliest.day)
            : null,
      ),
    );
    if (picked == null) return;

    setState(() {
      _rangeStart = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _rangeEnd = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
  }
}

class _CustomersPage extends StatefulWidget {
  const _CustomersPage({
    required this.customers,
    required this.bills,
    required this.appointments,
    required this.onAddCustomer,
    required this.onImportCustomers,
    required this.onImportPhoneContacts,
    required this.onEditCustomer,
    required this.onDeleteCustomer,
    required this.onDeleteAllCustomers,
    required this.onDeleteMultiple,
    required this.onUpdateCustomer,
    this.onAddBill,
  });

  final List<Customer> customers;
  final List<Bill> bills;
  final List<Appointment> appointments;
  final VoidCallback onAddCustomer;
  final Future<void> Function() onImportCustomers;
  final Future<void> Function() onImportPhoneContacts;
  final ValueChanged<Customer> onEditCustomer;
  final ValueChanged<Customer> onDeleteCustomer;
  final VoidCallback onDeleteAllCustomers;
  final void Function(List<Customer> customers) onDeleteMultiple;
  final Future<void> Function(Customer customer, Customer updatedCustomer)
      onUpdateCustomer;
  final void Function(Customer customer)? onAddBill;

  @override
  State<_CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<_CustomersPage> {
  String _query = '';
  bool _isImporting = false;
  bool _isImportingPhoneContacts = false;

  // ── Multi-select state ───────────────────────────────────────────────────
  final Set<String> _selectedIds = {};
  bool get _isSelecting => _selectedIds.isNotEmpty;

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<Customer> filtered) {
    setState(() {
      _selectedIds.addAll(filtered.map((c) => c.id));
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.red, size: 40),
        title: Text('Delete $count client${count == 1 ? '' : 's'}?'),
        content: Text(
          'This will permanently delete $count selected client${count == 1 ? '' : 's'}. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final toDelete =
        widget.customers.where((c) => _selectedIds.contains(c.id)).toList();
    _clearSelection();
    widget.onDeleteMultiple(toDelete);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.customers.where((customer) {
      final text = '${customer.name} ${customer.phone}'.toLowerCase();
      return text.contains(_query.toLowerCase());
    }).toList()
      ..sort((a, b) {
        // IDs are millisecond timestamps — higher = newer, show first
        final aTs = int.tryParse(a.id) ?? 0;
        final bTs = int.tryParse(b.id) ?? 0;
        return bTs.compareTo(aTs);
      });

    final primary = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            // Extra bottom padding when action bar is visible
            bottom: _isSelecting ? 88 : 16,
          ),
          children: [
            // ── Header — swaps to selection count when selecting ────────
            if (_isSelecting)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel selection',
                      onPressed: _clearSelection,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${_selectedIds.length} selected',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _selectAll(filtered),
                      child: const Text('Select All'),
                    ),
                  ],
                ),
              )
            else ...[
              _Header(
                  title: 'Clients',
                  subtitle: 'Search customers, notes, and pending dues.'),
              const SizedBox(height: 16),
              // ── Search + overflow menu row ──────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search name or phone'),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More options',
                    onSelected: (value) {
                      if (value == 'delete_all') _deleteAllCustomers();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'delete_all',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep_outlined,
                                color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete All Clients',
                                style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: widget.onAddCustomer,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Add Customer'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isImporting ? null : _importCustomers,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload Excel'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _isImportingPhoneContacts ? null : _importPhoneContacts,
                    icon: _isImportingPhoneContacts
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.contact_phone_outlined),
                    label: const Text('Phone Contacts'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // ── Customer tiles ────────────────────────────────────────────
            ...filtered.map((customer) {
              final isSelected = _selectedIds.contains(customer.id);
              return GestureDetector(
                onLongPress: () => _toggleSelect(customer.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primary.withValues(alpha: 0.1)
                        : _cardColor(context),
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected
                        ? Border.all(color: primary, width: 2)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: _softShadowColor(context),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListTile(
                    onTap: _isSelecting
                        ? () => _toggleSelect(customer.id)
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _CustomerDetailsPage(
                                  customer: customer,
                                  bills: widget.bills,
                                  appointments: widget.appointments,
                                  onUpdated: (updated) async => widget
                                      .onUpdateCustomer(customer, updated),
                                  onAddBill: widget.onAddBill != null
                                      ? () => widget.onAddBill!(customer)
                                      : null,
                                ),
                              ),
                            ),
                    onLongPress: () => _toggleSelect(customer.id),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: isSelected
                        ? CircleAvatar(
                            radius: 24,
                            backgroundColor: primary,
                            child: const Icon(Icons.check,
                                color: Colors.white, size: 20),
                          )
                        : CircleAvatar(
                            radius: 24,
                            backgroundColor: primary.withValues(alpha: 0.1),
                            child: Text(
                              customer.name.isEmpty
                                  ? '?'
                                  : customer.name[0].toUpperCase(),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, color: primary),
                            ),
                          ),
                    title: Text(customer.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(
                      '${customer.phone} • ${customer.note}'
                      '${customer.referredBy.isNotEmpty ? '\nReferred by: ${customer.referredBy}' : ''}',
                      style: TextStyle(
                          height: 1.4, color: _mutedTextColor(context)),
                    ),
                    trailing: _isSelecting
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit client',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () =>
                                    widget.onEditCustomer(customer),
                              ),
                              IconButton(
                                tooltip: 'Delete client',
                                icon: const Icon(Icons.delete_outline),
                                color: Colors.red,
                                onPressed: () =>
                                    widget.onDeleteCustomer(customer),
                              ),
                              IconButton(
                                icon: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      shape: BoxShape.circle),
                                  child: Icon(Icons.call,
                                      color: Colors.green.shade700, size: 20),
                                ),
                                onPressed: () async {
                                  final url =
                                      Uri.parse('tel:${customer.phone}');
                                  if (await canLaunchUrl(url)) {
                                    await launchUrl(url);
                                  }
                                },
                              ),
                            ],
                          ),
                  ),
                ),
              );
            }),
          ],
        ),

        // ── Floating action bar shown during multi-select ────────────────
        if (_isSelecting)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text(
                      '${_selectedIds.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text('Delete (${_selectedIds.length})'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _deleteAllCustomers() async {
    final count = widget.customers.length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No clients to delete')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.red, size: 40),
        title: const Text('Delete all clients?'),
        content: Text(
          'This will permanently delete all $count client${count == 1 ? '' : 's'}.\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _clearSelection();
    widget.onDeleteAllCustomers();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('All $count client${count == 1 ? '' : 's'} deleted'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _importCustomers() async {
    setState(() => _isImporting = true);
    try {
      await widget.onImportCustomers();
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _importPhoneContacts() async {
    setState(() => _isImportingPhoneContacts = true);
    try {
      await widget.onImportPhoneContacts();
    } finally {
      if (mounted) {
        setState(() => _isImportingPhoneContacts = false);
      }
    }
  }
}

class _PhoneContactImportDialog extends StatefulWidget {
  const _PhoneContactImportDialog({
    required this.contacts,
    required this.existingCustomers,
    required this.normalizePhone,
  });

  final List<_PhoneContactCustomer> contacts;
  final List<Customer> existingCustomers;
  final String Function(String value) normalizePhone;

  @override
  State<_PhoneContactImportDialog> createState() =>
      _PhoneContactImportDialogState();
}

class _PhoneContactImportDialogState extends State<_PhoneContactImportDialog> {
  String _query = '';
  late final Set<String> _existingPhones;
  late final Set<String> _existingNamePhone;
  final Set<String> _selectedPhones = {};

  @override
  void initState() {
    super.initState();
    _existingPhones = widget.existingCustomers
        .map((customer) => widget.normalizePhone(customer.phone))
        .where((phone) => phone.isNotEmpty)
        .toSet();
    _existingNamePhone = widget.existingCustomers
        .map((customer) =>
            '${customer.name.trim().toLowerCase()}|${widget.normalizePhone(customer.phone)}')
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = widget.contacts.where((contact) {
      final text = '${contact.name} ${contact.phone}'.toLowerCase();
      return query.isEmpty || text.contains(query);
    }).toList();

    final selectedContacts = widget.contacts
        .where((contact) =>
            _selectedPhones.contains(widget.normalizePhone(contact.phone)))
        .toList();

    return AlertDialog(
      title: const Text('Add Phone Contacts'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search phone contacts',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No matching contacts'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final contact = filtered[index];
                        final normalizedPhone =
                            widget.normalizePhone(contact.phone);
                        final isDuplicate = _isDuplicate(contact);
                        final isSelected =
                            _selectedPhones.contains(normalizedPhone);
                        final initial = contact.name.isEmpty
                            ? '?'
                            : contact.name[0].toUpperCase();

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: isDuplicate
                              ? null
                              : (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedPhones.add(normalizedPhone);
                                    } else {
                                      _selectedPhones.remove(normalizedPhone);
                                    }
                                  });
                                },
                          secondary: CircleAvatar(
                            radius: 16,
                            child: Text(
                              initial,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          title: Text(
                            contact.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            isDuplicate
                                ? '${contact.phone} - Already in app'
                                : contact.phone,
                            overflow: TextOverflow.ellipsis,
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: selectedContacts.isEmpty
              ? null
              : () => Navigator.pop(context, selectedContacts),
          icon: const Icon(Icons.person_add_alt_1),
          label: Text('Add (${selectedContacts.length})'),
        ),
      ],
    );
  }

  bool _isDuplicate(_PhoneContactCustomer contact) {
    final phone = widget.normalizePhone(contact.phone);
    final namePhone = '${contact.name.trim().toLowerCase()}|$phone';
    return phone.isNotEmpty
        ? _existingPhones.contains(phone)
        : _existingNamePhone.contains(namePhone);
  }
}

class _PhoneContactCustomer {
  const _PhoneContactCustomer({
    required this.name,
    required this.phone,
  });

  final String name;
  final String phone;
}

class _AppointmentsPage extends StatefulWidget {
  const _AppointmentsPage({
    required this.appointments,
    required this.onAddAppointment,
    required this.onAddAppointmentForDate,
    this.onOpenOnlineBookings,
    this.onAddConfirmedOnlineBooking,
    this.parlourName = '',
    this.shopPhone = '',
    this.shopAddress = '',
    required this.onEditAppointment,
    required this.onConfirmAppointment,
    required this.onMarkArrived,
    required this.onDeleteAppointment,
  });

  final List<Appointment> appointments;
  final VoidCallback onAddAppointment;
  final ValueChanged<DateTime> onAddAppointmentForDate;
  final VoidCallback? onOpenOnlineBookings;
  final Future<void> Function({
    required String customerName,
    required String customerPhone,
    required String serviceName,
    required DateTime date,
    required TimeOfDay time,
    required double amount,
  })? onAddConfirmedOnlineBooking;
  final String parlourName;
  final String shopPhone;
  final String shopAddress;
  final ValueChanged<Appointment> onEditAppointment;
  final ValueChanged<Appointment> onConfirmAppointment;
  final ValueChanged<Appointment> onMarkArrived;
  final ValueChanged<Appointment> onDeleteAppointment;

  @override
  State<_AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<_AppointmentsPage> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  List<OnlineBooking> _onlineBookings = [];
  Timer? _onlinePollingTimer;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDate = DateTime(today.year, today.month, today.day);
    _rangeStart = DateTime(2000, 1, 1);
    _rangeEnd = DateTime(today.year, today.month, today.day);
    _loadOnlineBookings();
    _onlinePollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadOnlineBookings(silent: true);
    });
  }

  @override
  void dispose() {
    _onlinePollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AppointmentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameMonth(_selectedDate, _visibleMonth)) {
      _selectedDate = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    }
  }

  Future<void> _loadOnlineBookings({bool silent = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('nupur_online_bookings_list');
      List<OnlineBooking> list = [];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        list = decoded.map((e) => OnlineBooking.fromJson(e as Map<String, dynamic>)).toList();
      }

      // 1. Fetch live from Render Backend API
      try {
        final apiList = await FirestoreBookingService.fetchFromBackendApi();
        if (apiList.isNotEmpty) {
          final map = {for (var b in list) b.id: b};
          for (var b in apiList) {
            map[b.id] = b;
          }
          list = map.values.toList();
        }
      } catch (_) {}

      // 2. Fetch from Firestore if configured
      final projId = await FirestoreBookingService.getProjectId();
      if (projId.isNotEmpty && projId != FirestoreBookingService.defaultProjectId) {
        try {
          final live = await FirestoreBookingService.fetchFromFirestore(projId);
          if (live.isNotEmpty) {
            final map = {for (var b in list) b.id: b};
            for (var b in live) {
              map[b.id] = b;
            }
            list = map.values.toList();
          }
        } catch (_) {}
      }

      await prefs.setString(
          'nupur_online_bookings_list', jsonEncode(list.map((e) => e.toJson()).toList()));

      if (mounted) {
        setState(() {
          _onlineBookings = list;
        });
      }
    } catch (_) {}
  }

  String _cleanPhoneForWhatsApp(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '91$digits';
    return digits;
  }

  TimeOfDay _parseTimeOfDay(String timeSlot) {
    try {
      final parts = timeSlot.split(' ');
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      final int minute = int.parse(timeParts[1]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && hour < 12) {
        hour += 12;
      }
      if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && hour == 12) {
        hour = 0;
      }
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return const TimeOfDay(hour: 10, minute: 0);
    }
  }

  Future<void> _confirmOnlineBookingDirectly(OnlineBooking booking) async {
    final timeOfDay = _parseTimeOfDay(booking.timeSlot);

    if (widget.onAddConfirmedOnlineBooking != null) {
      await widget.onAddConfirmedOnlineBooking!(
        customerName: booking.customerName,
        customerPhone: booking.customerPhone,
        serviceName: booking.serviceNames,
        date: booking.bookingDate,
        time: timeOfDay,
        amount: booking.totalAmount,
      );
    }

    // 1. Update status on Render Backend API & Firestore
    await FirestoreBookingService.updateStatusOnBackendApi(
      bookingId: booking.id,
      newStatus: 'Confirmed',
    );
    final projId = await FirestoreBookingService.getProjectId();
    if (projId.isNotEmpty && projId != FirestoreBookingService.defaultProjectId) {
      await FirestoreBookingService.updateStatusInFirestore(
        projectId: projId,
        docId: booking.id,
        newStatus: 'Confirmed',
      );
    }

    final updated = _onlineBookings
        .map((b) => b.id == booking.id ? b.copyWith(status: 'Confirmed') : b)
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'nupur_online_bookings_list', jsonEncode(updated.map((e) => e.toJson()).toList()));

    setState(() {
      _onlineBookings = updated;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ બુકિંગ કન્ફર્મ થયું: ${booking.customerName}! WhatsApp ખોલી રહ્યું છે...'),
        backgroundColor: Colors.green.shade700,
      ),
    );

    if (booking.customerPhone.isNotEmpty) {
      final phone = _cleanPhoneForWhatsApp(booking.customerPhone);
      final dateFormatted = DateFormat('dd/MM/yyyy').format(booking.bookingDate);
      final parlour = widget.parlourName.isNotEmpty ? widget.parlourName : 'Nupur Beauty Parlour';
      final address = widget.shopAddress.isNotEmpty
          ? widget.shopAddress
          : 'Nupur Beauty Parlour (Only for Ladies)';

      final message = '''
🌸 *${parlour}* 🌸
✨ *બુકિંગ કન્ફર્મેશન / Booking Confirmed* ✨

નમસ્તે *${booking.customerName}* જી! 🙏
તમારું બ્યુટી પાર્લર એપોઇન્ટમેન્ટ બુકિંગ કન્ફર્મ થઈ ગયું છે.
(Your appointment has been *CONFIRMED*!)

📋 *બુકિંગ આઈડી / Booking ID:* #${booking.bookingRef}
📅 *તારીખ / Date:* $dateFormatted
⏰ *સમય સ્લોટ / Time Slot:* ${booking.timeSlot}
💅 *સર્વિસ / Services:* ${booking.serviceNames}
💰 *કુલ અંદાજિત રકમ / Estimated Total:* ₹${booking.totalAmount.toStringAsFixed(0)}

📍 *સ્થળ / Address:* $address
📞 *સંપર્ક / Phone:* ${widget.shopPhone}

જો તમારે સમયમાં કોઈ ફેરફાર કરવો હોય તો કૃપા કરીને આ નંબર પર જાણ કરશો.
અમે તમારી સેવામાં હાજર રહીશું! આભાર! 💖
''';

      final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _rejectOnlineBookingDirectly(OnlineBooking booking) async {
    // 1. Update status on Render Backend API & Firestore
    await FirestoreBookingService.updateStatusOnBackendApi(
      bookingId: booking.id,
      newStatus: 'Cancelled',
    );
    final projId = await FirestoreBookingService.getProjectId();
    if (projId.isNotEmpty && projId != FirestoreBookingService.defaultProjectId) {
      await FirestoreBookingService.updateStatusInFirestore(
        projectId: projId,
        docId: booking.id,
        newStatus: 'Cancelled',
      );
    }

    final updated = _onlineBookings
        .map((b) => b.id == booking.id ? b.copyWith(status: 'Cancelled') : b)
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'nupur_online_bookings_list', jsonEncode(updated.map((e) => e.toJson()).toList()));

    setState(() {
      _onlineBookings = updated;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('❌ રિક્વેસ્ટ રદ થઈ. વેબસાઇટ પર સ્લોટ ફરીથી Free થઈ ગયો છે.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildDirectOnlineRequestTile(OnlineBooking req) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.shade400, width: 1.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.language_rounded, color: Colors.amber, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '🌐 નવી ઓનલાઇન બુકિંગ વિનંતી',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xff92400E)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Pending',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xff78350F)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            req.customerName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
          ),
          Text(
            '📱 ${req.customerPhone}  •  #${req.bookingRef}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 15, color: Color(0xff0369A1)),
                    const SizedBox(width: 4),
                    Text(
                      req.timeSlot,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xff0369A1)),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      req.serviceNames,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Text(
                  '₹${req.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.green),
                ),
              ],
            ),
          ),
          if (req.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '📝 નોંધ: ${req.notes}',
              style: TextStyle(
                  fontSize: 11.5, fontStyle: FontStyle.italic, color: Colors.amber.shade900),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _rejectOnlineBookingDirectly(req),
                  child: const Text('❌ રદ કરો (Reject)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff0369A1),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _confirmOnlineBookingDirectly(req),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: const Text('✅ કન્ફર્મ & WhatsApp',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedAppointments = _appointmentsForDate(_selectedDate);
    final rangeAppointments = _appointmentsForRange(_rangeStart, _rangeEnd);
    final todayAppointments = _appointmentsForDate(DateTime.now());
    final monthAppointments = widget.appointments
        .where((appointment) => _isSameMonth(appointment.date, _visibleMonth))
        .toList();
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final bookedDays = {
      for (final appointment in monthAppointments) appointment.date.day,
    }.length;
    final freeDays = daysInMonth - bookedDays;

    final datePendingRequests = _onlineBookings
        .where((b) =>
            b.status.toLowerCase() == 'pending' &&
            _isSameDay(b.bookingDate, _selectedDate))
        .toList();

    final allPendingRequests = _onlineBookings
        .where((b) => b.status.toLowerCase() == 'pending')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bookings',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'See busy days, free days, and appointment times.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _mutedTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onOpenOnlineBookings != null) ...[
              IconButton.filledTonal(
                tooltip: 'Online Bookings (વેબસાઇટ બુકિંગ)',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xff0369A1).withOpacity(0.12),
                  foregroundColor: const Color(0xff0369A1),
                  padding: const EdgeInsets.all(12),
                ),
                onPressed: widget.onOpenOnlineBookings,
                icon: const Icon(Icons.language_rounded),
              ),
              const SizedBox(width: 8),
            ],
            IconButton.tonal(
              tooltip: 'Refresh Bookings (રીફ્રેશ)',
              style: IconButton.styleFrom(
                backgroundColor: Colors.blue.shade50,
                foregroundColor: const Color(0xff0369A1),
                padding: const EdgeInsets.all(12),
              ),
              onPressed: () async {
                await _loadOnlineBookings();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🔄 ઓનલાઇન બુકિંગ રીફ્રેશ થઈ ગયું!'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: widget.onAddAppointment,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(14),
              ),
              child: const Icon(Icons.add),
            ),
          ],
        ),
        if (allPendingRequests.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xffFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.shade400, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(Icons.notification_important_rounded,
                    color: Colors.amber.shade800, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🔔 ${allPendingRequests.length} નવી ઓનલાઇન બુકિંગ વિનંતી!',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: Colors.amber.shade900),
                      ),
                      Text(
                        'ગ્રાહક: ${allPendingRequests.first.customerName} (${DateFormat('dd-MMM').format(allPendingRequests.first.bookingDate)} - ${allPendingRequests.first.timeSlot})',
                        style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: () {
                    final req = allPendingRequests.first;
                    setState(() {
                      _selectedDate = req.bookingDate;
                      _visibleMonth =
                          DateTime(req.bookingDate.year, req.bookingDate.month);
                    });
                  },
                  child: const Text('તપાસો', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _BookingSummaryTile(
                label: 'Today',
                value: '${todayAppointments.length}',
                icon: Icons.today_outlined,
                color: const Color(0xff2563EB),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BookingSummaryTile(
                label: 'Range',
                value: '${rangeAppointments.length}',
                icon: Icons.date_range,
                color: const Color(0xff0369A1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BookingSummaryTile(
                label: 'Free',
                value: '$freeDays',
                icon: Icons.event_available_outlined,
                color: const Color(0xff059669),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DateRangeField(
          start: _rangeStart,
          end: _rangeEnd,
          onTap: _openDateRangePicker,
        ),
        const SizedBox(height: 16),
        _BookingCalendar(
          visibleMonth: _visibleMonth,
          selectedDate: _selectedDate,
          appointments: widget.appointments,
          bookedDays: bookedDays,
          freeDays: freeDays,
          onPreviousMonth: () => setState(() {
            _visibleMonth =
                DateTime(_visibleMonth.year, _visibleMonth.month - 1);
            _selectedDate =
                DateTime(_visibleMonth.year, _visibleMonth.month, 1);
          }),
          onNextMonth: () => setState(() {
            _visibleMonth =
                DateTime(_visibleMonth.year, _visibleMonth.month + 1);
            _selectedDate =
                DateTime(_visibleMonth.year, _visibleMonth.month, 1);
          }),
          onSelectDate: (date) => setState(() => _selectedDate = date),
          onOpenDate: (date) {
            setState(() => _selectedDate = date);
            widget.onAddAppointmentForDate(date);
          },
        ),
        const SizedBox(height: 16),
        _SectionTitle(_selectedDateLabel(context, _selectedDate)),
        const SizedBox(height: 8),

        // 1. Direct Online Booking Requests on this selected day
        ...datePendingRequests.map((req) => _buildDirectOnlineRequestTile(req)),

        // 2. Confirmed / existing appointments on this selected day
        if (selectedAppointments.isEmpty && datePendingRequests.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardColor(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.event_available_outlined,
                    color: Colors.green.shade700),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'No bookings. This day is free.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          )
        else
          ...selectedAppointments.map((appointment) => _AppointmentTile(
                appointment: appointment,
                onEdit: () => widget.onEditAppointment(appointment),
                onConfirm: () => widget.onConfirmAppointment(appointment),
                onArrived: () => widget.onMarkArrived(appointment),
                onDelete: () => widget.onDeleteAppointment(appointment),
              )),
      ],
    );
  }

  List<Appointment> _appointmentsForDate(DateTime date) {
    return widget.appointments
        .where((appointment) => _isSameDay(appointment.date, date))
        .toList()
      ..sort((a, b) {
        final aMinutes = a.time.hour * 60 + a.time.minute;
        final bMinutes = b.time.hour * 60 + b.time.minute;
        return aMinutes.compareTo(bMinutes);
      });
  }

  List<Appointment> _appointmentsForRange(DateTime start, DateTime end) {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    return widget.appointments.where((appointment) {
      final date = DateTime(
        appointment.date.year,
        appointment.date.month,
        appointment.date.day,
      );
      return !date.isBefore(normalizedStart) && !date.isAfter(normalizedEnd);
    }).toList()
      ..sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        final aMinutes = a.time.hour * 60 + a.time.minute;
        final bMinutes = b.time.hour * 60 + b.time.minute;
        return aMinutes.compareTo(bMinutes);
      });
  }

  Future<void> _openDateRangePicker() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final allDates = widget.appointments.map((a) => a.date).toList();
    final earliest = allDates.isEmpty
        ? null
        : allDates.reduce((a, b) => a.isBefore(b) ? a : b);

    final result = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => _BookingDateRangeDialog(
        initialStart: _rangeStart,
        initialEnd: _rangeEnd,
        initialPreset: 'All Time',
        earliestDate: earliest != null
            ? DateTime(earliest.year, earliest.month, earliest.day)
            : null,
      ),
    );
    if (result == null) return;

    setState(() {
      _rangeStart = DateTime(
        result.start.year,
        result.start.month,
        result.start.day,
      );
      _rangeEnd = DateTime(result.end.year, result.end.month, result.end.day);
      _selectedDate = _rangeStart;
      _visibleMonth = DateTime(_rangeStart.year, _rangeStart.month);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  String _selectedDateLabel(BuildContext context, DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} bookings';
  }
}

class _BookingSummaryTile extends StatelessWidget {
  const _BookingSummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _isDarkMode(context)
                ? Colors.black.withOpacity(0.24)
                : color.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: _mutedTextColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRangeField extends StatelessWidget {
  const _DateRangeField({
    required this.start,
    required this.end,
    required this.onTap,
  });

  final DateTime start;
  final DateTime end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_outlined,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Date Range',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: _cardColor(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isDarkMode(context)
                      ? Colors.white.withOpacity(0.1)
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_formatDate(start)} - ${_formatDate(end)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _BookingDateRangeDialog extends StatefulWidget {
  const _BookingDateRangeDialog({
    required this.initialStart,
    required this.initialEnd,
    this.earliestDate,
    this.initialPreset,
  });

  final DateTime initialStart;
  final DateTime initialEnd;
  final DateTime? earliestDate;
  final String? initialPreset;

  @override
  State<_BookingDateRangeDialog> createState() =>
      _BookingDateRangeDialogState();
}

class _BookingDateRangeDialogState extends State<_BookingDateRangeDialog> {
  late DateTime _start;
  late DateTime _end;
  late DateTime _visibleMonth;
  late String _selectedPreset;

  static const _presets = [
    'All Time',
    'Today',
    'Yesterday',
    'Last 7 Days',
    'Last 30 Days',
    'This Month',
    'Last Month',
    'This Month Last Year',
    'This Year',
    'Last Year',
    'This Financial Year',
    'Last Financial Year',
    'Custom Range',
  ];

  @override
  void initState() {
    super.initState();
    _start = _onlyDate(widget.initialStart);
    _end = _onlyDate(widget.initialEnd);
    _visibleMonth = DateTime(_start.year, _start.month);
    _selectedPreset = widget.initialPreset ?? 'Custom Range';
  }

  @override
  Widget build(BuildContext context) {
    final nextMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 620;
                final presets = _PresetList(
                  presets: _presets,
                  selectedPreset: _selectedPreset,
                  onSelected: _applyPreset,
                );
                final calendars = Expanded(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _monthGrid(_visibleMonth, showPrev: true, showNext: false)),
                                const SizedBox(width: 14),
                                Expanded(child: _monthGrid(nextMonth, showPrev: false, showNext: true)),
                              ],
                            )
                          : _monthGrid(_visibleMonth),
                    ],
                  ),
                );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Date Range:',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        '${_formatDate(_start)} - ${_formatDate(_end)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 190, child: presets),
                          const SizedBox(width: 16),
                          calendars,
                        ],
                      )
                    else ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final preset in _presets) ...[
                              ChoiceChip(
                                label: Text(preset),
                                selected: _selectedPreset == preset,
                                onSelected: (_) => _applyPreset(preset),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _monthGrid(_visibleMonth),
                    ],
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_formatDate(_start)} - ${_formatDate(_end)}',
                            textAlign: TextAlign.right,
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(
                            context,
                            DateTimeRange(start: _start, end: _end),
                          ),
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthGrid(DateTime month, {bool showPrev = true, bool showNext = true}) {
    return _RangeMonthGrid(
      month: month,
      start: _start,
      end: _end,
      onSelect: _selectDate,
      onPrevMonth: showPrev
          ? () => setState(() {
                _visibleMonth = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month - 1,
                );
              })
          : null,
      onNextMonth: showNext
          ? () => setState(() {
                _visibleMonth = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month + 1,
                );
              })
          : null,
    );
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedPreset = 'Custom Range';
      final selected = _onlyDate(date);
      if (selected.isBefore(_start) || !_start.isAtSameMomentAs(_end)) {
        _start = selected;
        _end = selected;
      } else {
        _end = selected;
      }
      if (_end.isBefore(_start)) {
        final oldStart = _start;
        _start = _end;
        _end = oldStart;
      }
    });
  }

  void _applyPreset(String preset) {
    final now = _onlyDate(DateTime.now());
    late DateTime start;
    late DateTime end;

    switch (preset) {
      case 'All Time':
        start = widget.earliestDate ?? DateTime(2000, 1, 1);
        end = now;
        break;
      case 'Today':
        start = now;
        end = now;
        break;
      case 'Yesterday':
        start = now.subtract(const Duration(days: 1));
        end = start;
        break;
      case 'Last 7 Days':
        start = now.subtract(const Duration(days: 6));
        end = now;
        break;
      case 'Last 30 Days':
        start = now.subtract(const Duration(days: 29));
        end = now;
        break;
      case 'This Month':
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      case 'Last Month':
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(now.year, now.month, 0);
        break;
      case 'This Month Last Year':
        start = DateTime(now.year - 1, now.month, 1);
        end = DateTime(now.year - 1, now.month + 1, 0);
        break;
      case 'This Year':
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31);
        break;
      case 'Last Year':
        start = DateTime(now.year - 1, 1, 1);
        end = DateTime(now.year - 1, 12, 31);
        break;
      case 'This Financial Year':
        final fyStart = now.month >= 4 ? now.year : now.year - 1;
        start = DateTime(fyStart, 4, 1);
        end = DateTime(fyStart + 1, 3, 31);
        break;
      case 'Last Financial Year':
        final currentFyStart = now.month >= 4 ? now.year : now.year - 1;
        start = DateTime(currentFyStart - 1, 4, 1);
        end = DateTime(currentFyStart, 3, 31);
        break;
      default:
        start = _start;
        end = _end;
        break;
    }

    setState(() {
      _selectedPreset = preset;
      _start = start;
      _end = end;
      _visibleMonth = DateTime(start.year, start.month);
    });
  }

  DateTime _onlyDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _PresetList extends StatelessWidget {
  const _PresetList({
    required this.presets,
    required this.selectedPreset,
    required this.onSelected,
  });

  final List<String> presets;
  final String selectedPreset;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final preset in presets)
            InkWell(
              onTap: () => onSelected(preset),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                color: selectedPreset == preset
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                child: Text(
                  preset,
                  style: TextStyle(
                    color: selectedPreset == preset
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: selectedPreset == preset
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RangeMonthGrid extends StatelessWidget {
  const _RangeMonthGrid({
    required this.month,
    required this.start,
    required this.end,
    required this.onSelect,
    this.onPrevMonth,
    this.onNextMonth,
  });

  final DateTime month;
  final DateTime start;
  final DateTime end;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = firstDay.weekday % 7;
    final totalCells = ((leading + daysInMonth) / 7).ceil() * 7;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (onPrevMonth != null)
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous month',
                onPressed: onPrevMonth,
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            else
              const SizedBox(width: 32),
            Text(
              '${_monthNames[month.month - 1]} ${month.year}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            if (onNextMonth != null)
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next month',
                onPressed: onNextMonth,
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            else
              const SizedBox(width: 32),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: const [
            _WeekdayLabel('Su'),
            _WeekdayLabel('Mo'),
            _WeekdayLabel('Tu'),
            _WeekdayLabel('We'),
            _WeekdayLabel('Th'),
            _WeekdayLabel('Fr'),
            _WeekdayLabel('Sa'),
          ],
        ),
        const SizedBox(height: 6),
        // Build the calendar grid manually to avoid GridView sizing issues
        // inside scrollable dialogs.
        Builder(builder: (context) {
          final rows = <Widget>[];
          for (int rowStart = 0; rowStart < totalCells; rowStart += 7) {
            final cells = <Widget>[];
            for (int col = 0; col < 7; col++) {
              final index = rowStart + col;
              final day = index - leading + 1;
              if (day < 1 || day > daysInMonth) {
                cells.add(const Expanded(child: SizedBox()));
              } else {
                final date = DateTime(month.year, month.month, day);
                final selected =
                    _isSameDay(date, start) || _isSameDay(date, end);
                final inRange = !date.isBefore(start) && !date.isAfter(end);
                final primary = Theme.of(context).colorScheme.primary;
                cells.add(
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => onSelect(date),
                      child: Container(
                        height: 36,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 2),
                        decoration: BoxDecoration(
                          color: selected
                              ? primary
                              : inRange
                                  ? primary.withValues(alpha: 0.12)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$day',
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight:
                                selected ? FontWeight.w900 : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
            }
            rows.add(Row(children: cells));
          }
          return Column(children: rows);
        }),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _CompactAppointmentRow extends StatelessWidget {
  const _CompactAppointmentRow({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${appointment.date.day.toString().padLeft(2, '0')}/${appointment.date.month.toString().padLeft(2, '0')} '
              '${appointment.time.format(context)} - ${appointment.customerName} (${appointment.serviceName})',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingCalendar extends StatelessWidget {
  const _BookingCalendar({
    required this.visibleMonth,
    required this.selectedDate,
    required this.appointments,
    required this.bookedDays,
    required this.freeDays,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onSelectDate,
    required this.onOpenDate,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final List<Appointment> appointments;
  final int bookedDays;
  final int freeDays;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<DateTime> onOpenDate;

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth =
        DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leadingEmptyCells = firstDay.weekday % 7;
    final totalCells = leadingEmptyCells + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    final cellCount = rowCount * 7;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _softShadowColor(context),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: onPreviousMonth,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '${_monthNames[visibleMonth.month - 1]} ${visibleMonth.year}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$bookedDays booked days • $freeDays free days',
                      style: TextStyle(color: _mutedTextColor(context)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: onNextMonth,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              _WeekdayLabel('S'),
              _WeekdayLabel('M'),
              _WeekdayLabel('T'),
              _WeekdayLabel('W'),
              _WeekdayLabel('T'),
              _WeekdayLabel('F'),
              _WeekdayLabel('S'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cellCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.62,
            ),
            itemBuilder: (context, index) {
              final dayNumber = index - leadingEmptyCells + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const SizedBox.shrink();
              }

              final date =
                  DateTime(visibleMonth.year, visibleMonth.month, dayNumber);
              final dayAppointments = appointments
                  .where((appointment) => _isSameDay(appointment.date, date))
                  .toList()
                ..sort((a, b) {
                  final aMinutes = a.time.hour * 60 + a.time.minute;
                  final bMinutes = b.time.hour * 60 + b.time.minute;
                  return aMinutes.compareTo(bMinutes);
                });

              return _CalendarDayTile(
                date: date,
                appointments: dayAppointments,
                selected: _isSameDay(date, selectedDate),
                today: _isSameDay(date, DateTime.now()),
                onTap: () => onSelectDate(date),
                onDoubleTap: () => onOpenDate(date),
              );
            },
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: _mutedTextColor(context),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CalendarDayTile extends StatelessWidget {
  const _CalendarDayTile({
    required this.date,
    required this.appointments,
    required this.selected,
    required this.today,
    required this.onTap,
    required this.onDoubleTap,
  });

  final DateTime date;
  final List<Appointment> appointments;
  final bool selected;
  final bool today;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final hasBookings = appointments.isNotEmpty;
    final primary = Theme.of(context).colorScheme.primary;
    final firstTime =
        hasBookings ? appointments.first.time.format(context) : 'Free';

    return Material(
      color: selected
          ? primary
          : hasBookings
              ? const Color(0xffEFF6FF)
              : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? primary
                  : today
                      ? primary
                      : const Color(0xffCBD5E1),
              width: selected || today ? 1.8 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : const Color(0xff0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: hasBookings
                    ? BoxDecoration(
                        color: selected
                            ? Colors.white.withOpacity(0.22)
                            : const Color(0xff0369A1).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                      )
                    : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    hasBookings ? '${appointments.length}' : 'Free',
                    maxLines: 1,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : hasBookings
                              ? const Color(0xff0369A1)
                              : const Color(0xff334155),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              if (hasBookings) ...[
                const SizedBox(height: 1),
                Flexible(
                  child: Text(
                    firstTime,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? Colors.white.withOpacity(0.9)
                          : const Color(0xff0369A1),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BillingPage extends StatefulWidget {
  const _BillingPage({
    required this.bills,
    required this.onAddBill,
    required this.onEditBill,
    required this.onDeleteBill,
    required this.onShareBill,
    required this.onExportBill,
  });

  final List<Bill> bills;
  final VoidCallback onAddBill;
  final ValueChanged<Bill> onEditBill;
  final ValueChanged<Bill> onDeleteBill;
  final ValueChanged<Bill> onShareBill;
  final ValueChanged<Bill> onExportBill;

  @override
  State<_BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<_BillingPage> {
  String _filterType = 'All Time';
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    List<Bill> filteredBills = widget.bills;

    if (_filterType == 'Daily') {
      filteredBills = widget.bills
          .where((b) =>
              b.date.year == _selectedDate.year &&
              b.date.month == _selectedDate.month &&
              b.date.day == _selectedDate.day)
          .toList();
    } else if (_filterType == 'Monthly') {
      filteredBills = widget.bills
          .where((b) =>
              b.date.year == _selectedDate.year &&
              b.date.month == _selectedDate.month)
          .toList();
    } else if (_filterType == 'Yearly') {
      filteredBills =
          widget.bills.where((b) => b.date.year == _selectedDate.year).toList();
    }

    // Newest first
    filteredBills = [...filteredBills]..sort((a, b) => b.date.compareTo(a.date));

    final totalIncome =
        filteredBills.fold<double>(0, (total, bill) => total + bill.total);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(
            title: 'Bills',
            subtitle: 'Filter by date/month and track total income.'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _filterType,
                items: ['All Time', 'Daily', 'Monthly', 'Yearly']
                    .map((type) =>
                        DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (value) => setState(() => _filterType = value!),
                decoration: InputDecoration(
                  labelText: 'Filter By',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            if (_filterType != 'All Time') ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030));
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_filterType == 'Yearly'
                      ? '${_selectedDate.year}'
                      : _filterType == 'Monthly'
                          ? '${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}'
                          : '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: widget.onAddBill,
          icon: const Icon(Icons.receipt_long),
          label: const Text('Create New Bill'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
        ),
        const SizedBox(height: 16),
        ...filteredBills.map((bill) => _BillTileV2(
              bill: bill,
              onEdit: () => widget.onEditBill(bill),
              onDelete: () => widget.onDeleteBill(bill),
              onShare: () => widget.onShareBill(bill),
              onExportPdf: () => widget.onExportBill(bill),
            )),
        if (filteredBills.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Income',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(money(totalIncome),
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (filteredBills.isEmpty)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No bills found for this period.'))),
      ],
    );
  }
}

class _ServicesPage extends StatelessWidget {
  const _ServicesPage({
    required this.services,
    required this.onAddService,
    required this.onEditService,
    required this.onDeleteService,
  });

  final List<ParlourService> services;
  final VoidCallback onAddService;
  final ValueChanged<ParlourService> onEditService;
  final ValueChanged<ParlourService> onDeleteService;

  @override
  Widget build(BuildContext context) {
    final categories =
        services.map((service) => service.category).toSet().toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(
            title: 'Services',
            subtitle: 'Your price list with duration and categories.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onAddService,
          icon: const Icon(Icons.add),
          label: const Text('Add Service'),
        ),
        const SizedBox(height: 16),
        for (final category in categories) ...[
          _SectionTitle(category),
          const SizedBox(height: 8),
          ...services
              .where((service) => service.category == category)
              .map((service) => _ServiceTile(
                    service: service,
                    onEdit: () => onEditService(service),
                    onDelete: () => onDeleteService(service),
                  )),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _PurchasesPage extends StatefulWidget {
  const _PurchasesPage({
    required this.purchases,
    required this.onAddPurchase,
    required this.onEditPurchase,
    required this.onDeletePurchase,
  });

  final List<PurchaseItem> purchases;
  final VoidCallback onAddPurchase;
  final ValueChanged<PurchaseItem> onEditPurchase;
  final ValueChanged<PurchaseItem> onDeletePurchase;

  @override
  State<_PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<_PurchasesPage> {
  int _filterIndex = 3; // default: All Time
  PaymentMode? _paymentFilter;
  DateTime _selectedDate = DateTime.now();

  List<PurchaseItem> get _filteredPurchases {
    final now = _selectedDate;
    return widget.purchases.where((purchase) {
      if (_paymentFilter != null && purchase.paymentMode != _paymentFilter) {
        return false;
      }

      final date = purchase.dateTime;
      switch (_filterIndex) {
        case 0:
          return date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        case 1:
          return date.year == now.year && date.month == now.month;
        case 2:
          return date.year == now.year;
        case 3: // All Time
          return true;
        default:
          return true;
      }
    }).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  double get _filteredTotal =>
      _filteredPurchases.fold(0, (sum, purchase) => sum + purchase.total);

  double get _filteredCashTotal => _filteredPurchases
      .where((purchase) => purchase.paymentMode == PaymentMode.cash)
      .fold(0, (sum, purchase) => sum + purchase.total);

  String get _periodLabel {
    final d = _selectedDate;
    switch (_filterIndex) {
      case 0:
        return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      case 1:
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        return '${months[d.month - 1]} ${d.year}';
      case 2:
        return '${d.year}';
      case 3:
        return 'All Time';
      default:
        return '';
    }
  }

  void _goBack() {
    if (_filterIndex == 3) return;
    setState(() {
      switch (_filterIndex) {
        case 0:
          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
          break;
        case 1:
          _selectedDate = DateTime(
            _selectedDate.month == 1
                ? _selectedDate.year - 1
                : _selectedDate.year,
            _selectedDate.month == 1 ? 12 : _selectedDate.month - 1,
          );
          break;
        case 2:
          _selectedDate = DateTime(_selectedDate.year - 1);
          break;
      }
    });
  }

  void _goForward() {
    if (_filterIndex == 3) return;
    final now = DateTime.now();
    setState(() {
      switch (_filterIndex) {
        case 0:
          final next = _selectedDate.add(const Duration(days: 1));
          if (!next.isAfter(now)) _selectedDate = next;
          break;
        case 1:
          final nextMonth = _selectedDate.month == 12
              ? DateTime(_selectedDate.year + 1, 1)
              : DateTime(_selectedDate.year, _selectedDate.month + 1);
          if (!nextMonth.isAfter(now)) _selectedDate = nextMonth;
          break;
        case 2:
          if (_selectedDate.year < now.year) {
            _selectedDate = DateTime(_selectedDate.year + 1);
          }
          break;
      }
    });
  }

  Future<void> _exportPurchasePdf() async {
    final purchases = _filteredPurchases;
    final periodType = switch (_filterIndex) {
      0 => 'Daily',
      1 => 'Monthly',
      2 => 'Yearly',
      _ => 'All Time',
    };
    final bytes = await _buildPurchasePdf(
      purchases: purchases,
      periodLabel: _periodLabel,
      periodType: periodType,
      paymentLabel: _paymentFilter?.label ?? 'All',
      total: _filteredTotal,
    );
    final safePeriod = _periodLabel.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'purchase_${safePeriod.toLowerCase()}.pdf',
    );
  }

  Future<void> _exportPurchaseInvoicePdf(PurchaseItem purchase) async {
    final invoiceItems = widget.purchases
        .where((item) => item.invoiceId == purchase.invoiceId)
        .toList()
      ..sort((a, b) => a.itemName.compareTo(b.itemName));
    final bytes = await _buildPurchaseInvoicePdf(
      invoiceId: purchase.invoiceId,
      purchases: invoiceItems.isEmpty ? [purchase] : invoiceItems,
    );
    final fileName =
        '${purchase.invoiceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  Future<Uint8List> _buildPurchaseInvoicePdf({
    required String invoiceId,
    required List<PurchaseItem> purchases,
  }) async {
    final first = purchases.first;
    final total =
        purchases.fold<double>(0, (sum, purchase) => sum + purchase.total);
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Purchase Invoice',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 14),
              _purchasePdfInfoRow('Invoice No.', invoiceId),
              _purchasePdfInfoRow('Dealer',
                  first.dealer.trim().isEmpty ? '-' : first.dealer.trim()),
              _purchasePdfInfoRow('Date', _purchasePdfDate(first.dateTime)),
              _purchasePdfInfoRow('Payment', first.paymentMode.label),
              pw.SizedBox(height: 18),
              pw.Table(
                border: pw.TableBorder.all(width: 0.4),
                columnWidths: const {
                  0: pw.FlexColumnWidth(),
                  1: pw.FixedColumnWidth(80),
                  2: pw.FixedColumnWidth(55),
                  3: pw.FixedColumnWidth(90),
                },
                children: [
                  _purchasePdfRow(
                    ['Item', 'Price', 'Qty', 'Total'],
                    isHeader: true,
                  ),
                  ...purchases.map(
                    (purchase) => _purchasePdfRow([
                      purchase.itemName,
                      money(purchase.unitPrice),
                      _formatQuantity(purchase.quantity),
                      money(purchase.total),
                    ]),
                  ),
                ],
              ),
              pw.Divider(height: 28),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Total',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    money(total),
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _buildPurchasePdf({
    required List<PurchaseItem> purchases,
    required String periodLabel,
    required String periodType,
    required String paymentLabel,
    required double total,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            '$periodType Purchase Report',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Period: $periodLabel'),
          pw.Text('Payment: $paymentLabel'),
          pw.SizedBox(height: 14),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Items: ${purchases.length}'),
              pw.Text(
                'Total: ${money(total)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.Divider(height: 24),
          if (purchases.isEmpty)
            pw.Text('No purchases for this period.')
          else
            pw.Table(
              border: pw.TableBorder.all(width: 0.4),
              columnWidths: const {
                0: pw.FixedColumnWidth(54),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1),
                3: pw.FixedColumnWidth(58),
                4: pw.FixedColumnWidth(42),
                5: pw.FixedColumnWidth(52),
                6: pw.FixedColumnWidth(62),
              },
              children: [
                _purchasePdfRow(
                  ['Date', 'Item', 'Dealer', 'Price', 'Qty', 'Mode', 'Total'],
                  isHeader: true,
                ),
                ...purchases.map(
                  (purchase) => _purchasePdfRow([
                    _purchasePdfDate(purchase.dateTime),
                    purchase.itemName,
                    purchase.dealer.isEmpty ? '-' : purchase.dealer,
                    money(purchase.unitPrice),
                    _formatQuantity(purchase.quantity),
                    purchase.paymentMode.label,
                    money(purchase.total),
                  ]),
                ),
              ],
            ),
        ],
      ),
    );
    return doc.save();
  }

  pw.TableRow _purchasePdfRow(List<String> values, {bool isHeader = false}) {
    return pw.TableRow(
      decoration: isHeader
          ? const pw.BoxDecoration(color: PdfColor.fromInt(0xffeeeeee))
          : null,
      children: values.map((value) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _purchasePdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  String _purchasePdfDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [..._filteredPurchases]
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final totalSpend = _filteredTotal;
    final cashSpend = _filteredCashTotal;
    final onlineSpend = totalSpend - cashSpend;
    final primary = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(
          title: 'Purchases',
          subtitle: 'Track items, dealers, quantity, payment, and timing.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: widget.onAddPurchase,
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Add Purchase'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: ['Daily', 'Monthly', 'Yearly', 'All Time'].asMap().entries.map((e) {
              final selected = _filterIndex == e.key;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _filterIndex = e.key;
                    _selectedDate = DateTime.now();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      e.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color:
                            selected ? Colors.white : _mutedTextColor(context),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        if (_filterIndex != 3)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _cardColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isDarkMode(context)
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _goBack,
                color: primary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                _periodLabel,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _goForward,
                color: primary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<PaymentMode?>(
          segments: const [
            ButtonSegment(
              value: null,
              icon: Icon(Icons.receipt_long_outlined),
              label: Text('All'),
            ),
            ButtonSegment(
              value: PaymentMode.cash,
              icon: Icon(Icons.payments_outlined),
              label: Text('Cash'),
            ),
            ButtonSegment(
              value: PaymentMode.online,
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: Text('Online'),
            ),
          ],
          selected: {_paymentFilter},
          onSelectionChanged: (selection) =>
              setState(() => _paymentFilter = selection.first),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _exportPurchasePdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Export PDF'),
        ),
        const SizedBox(height: 16),
        _MetricGrid(
          metrics: [
            _Metric(
              'Total Purchase',
              money(totalSpend),
              Icons.shopping_bag,
              const Color(0xffbe185d),
            ),
            _Metric(
              'Items',
              sorted.length.toString(),
              Icons.inventory_2_outlined,
              const Color(0xff2563eb),
            ),
            _Metric(
              'Cash',
              money(cashSpend),
              Icons.payments_outlined,
              const Color(0xff059669),
            ),
            _Metric(
              'Online',
              money(onlineSpend),
              Icons.account_balance_wallet_outlined,
              const Color(0xff7c3aed),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const _SectionTitle('Purchase History'),
            const Spacer(),
            Text(
              '${sorted.length} item${sorted.length == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.shopping_bag_outlined,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'No purchases added yet.',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          )
        else
          ...sorted.map(
            (purchase) => _PurchaseTile(
              purchase: purchase,
              onEdit: () => widget.onEditPurchase(purchase),
              onDelete: () => widget.onDeletePurchase(purchase),
              onExportPdf: () => _exportPurchaseInvoicePdf(purchase),
            ),
          ),
      ],
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({
    required this.purchase,
    required this.onEdit,
    required this.onDelete,
    required this.onExportPdf,
  });

  final PurchaseItem purchase;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    final date =
        '${purchase.dateTime.day.toString().padLeft(2, '0')}/${purchase.dateTime.month.toString().padLeft(2, '0')}/${purchase.dateTime.year}';
    final time = TimeOfDay.fromDateTime(purchase.dateTime).format(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isDarkMode(context)
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: _softShadowColor(context),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xffbe185d).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: Color(0xffbe185d),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            purchase.itemName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          money(purchase.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dealer: ${purchase.dealer.isEmpty ? '-' : purchase.dealer}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _mutedTextColor(context)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Invoice: ${purchase.invoiceId}',
                      style: TextStyle(
                        color: _mutedTextColor(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Price ${money(purchase.unitPrice)} x Qty ${_formatQuantity(purchase.quantity)}',
                      style: TextStyle(color: _mutedTextColor(context)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$date $time • ${purchase.paymentMode.label}',
                      style: TextStyle(
                        color: _mutedTextColor(context),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Export purchase invoice PDF',
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          color: Colors.red,
                          onPressed: onExportPdf,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          tooltip: 'Edit purchase',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: onEdit,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          tooltip: 'Delete purchase',
                          icon: const Icon(Icons.delete_outline),
                          color: Colors.red,
                          onPressed: onDelete,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatQuantity(double quantity) {
  return quantity % 1 == 0 ? quantity.toStringAsFixed(0) : quantity.toString();
}

class _InvestmentsPage extends StatefulWidget {
  const _InvestmentsPage({
    required this.investments,
    required this.onAddInvestment,
    required this.onEditInvestment,
    required this.onDeleteInvestment,
  });

  final List<InvestmentTransaction> investments;
  final VoidCallback onAddInvestment;
  final ValueChanged<InvestmentTransaction> onEditInvestment;
  final ValueChanged<InvestmentTransaction> onDeleteInvestment;

  @override
  State<_InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<_InvestmentsPage> {
  int _filterIndex = 3; // 0: Daily, 1: Monthly, 2: Yearly, 3: All Time
  InvestmentType? _typeFilter;
  PaymentMode? _paymentFilter;
  DateTime _selectedDate = DateTime.now();

  List<InvestmentTransaction> get _filteredInvestments {
    final now = _selectedDate;
    return widget.investments.where((item) {
      if (_typeFilter != null && item.type != _typeFilter) {
        return false;
      }
      if (_paymentFilter != null && item.paymentMode != _paymentFilter) {
        return false;
      }

      final date = item.dateTime;
      switch (_filterIndex) {
        case 0:
          return date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        case 1:
          return date.year == now.year && date.month == now.month;
        case 2:
          return date.year == now.year;
        case 3:
          return true;
        default:
          return true;
      }
    }).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  double get _totalCredit => _filteredInvestments
      .where((e) => e.type == InvestmentType.credit)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get _totalDebit => _filteredInvestments
      .where((e) => e.type == InvestmentType.debit)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get _netBalance => _totalCredit - _totalDebit;

  double get _creditCash => _filteredInvestments
      .where((e) =>
          e.type == InvestmentType.credit && e.paymentMode == PaymentMode.cash)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get _creditOnline => _filteredInvestments
      .where((e) =>
          e.type == InvestmentType.credit && e.paymentMode == PaymentMode.online)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get _debitCash => _filteredInvestments
      .where((e) =>
          e.type == InvestmentType.debit && e.paymentMode == PaymentMode.cash)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get _debitOnline => _filteredInvestments
      .where((e) =>
          e.type == InvestmentType.debit && e.paymentMode == PaymentMode.online)
      .fold(0.0, (sum, e) => sum + e.amount);

  String get _periodLabel {
    final d = _selectedDate;
    switch (_filterIndex) {
      case 0:
        return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      case 1:
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        return '${months[d.month - 1]} ${d.year}';
      case 2:
        return '${d.year}';
      case 3:
        return 'All Time';
      default:
        return '';
    }
  }

  void _goBack() {
    if (_filterIndex == 3) return;
    setState(() {
      switch (_filterIndex) {
        case 0:
          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
          break;
        case 1:
          _selectedDate = DateTime(
            _selectedDate.month == 1
                ? _selectedDate.year - 1
                : _selectedDate.year,
            _selectedDate.month == 1 ? 12 : _selectedDate.month - 1,
          );
          break;
        case 2:
          _selectedDate = DateTime(_selectedDate.year - 1);
          break;
      }
    });
  }

  void _goForward() {
    if (_filterIndex == 3) return;
    final now = DateTime.now();
    setState(() {
      switch (_filterIndex) {
        case 0:
          final next = _selectedDate.add(const Duration(days: 1));
          if (!next.isAfter(now)) _selectedDate = next;
          break;
        case 1:
          final nextMonth = _selectedDate.month == 12
              ? DateTime(_selectedDate.year + 1, 1)
              : DateTime(_selectedDate.year, _selectedDate.month + 1);
          if (!nextMonth.isAfter(now)) _selectedDate = nextMonth;
          break;
        case 2:
          if (_selectedDate.year < now.year) {
            _selectedDate = DateTime(_selectedDate.year + 1);
          }
          break;
      }
    });
  }

  Future<void> _exportInvestmentPdf() async {
    final list = _filteredInvestments;
    final periodType = switch (_filterIndex) {
      0 => 'Daily',
      1 => 'Monthly',
      2 => 'Yearly',
      _ => 'All Time',
    };
    final typeLabel = switch (_typeFilter) {
      InvestmentType.credit => 'Credit (Invest) Only',
      InvestmentType.debit => 'Debit Only',
      _ => 'All Types',
    };
    final paymentLabel = _paymentFilter?.label ?? 'All';

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            '$periodType Investment Statement',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
              'Period: $_periodLabel | Filter: $typeLabel | Payment: $paymentLabel'),
          pw.SizedBox(height: 14),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Credit (Invest): ${money(_totalCredit)}',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xff059669))),
              pw.Text('Total Debit: ${money(_totalDebit)}',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xffdc2626))),
              pw.Text('Net Balance: ${money(_netBalance)}',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xff2563eb))),
            ],
          ),
          pw.Divider(height: 20),
          if (list.isEmpty)
            pw.Text('No investment transactions for this period.')
          else
            pw.Table(
              border: pw.TableBorder.all(width: 0.4),
              columnWidths: const {
                0: pw.FixedColumnWidth(65),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FixedColumnWidth(65),
                3: pw.FixedColumnWidth(55),
                4: pw.FixedColumnWidth(75),
                5: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xffeeeeee)),
                  children: [
                    'Date',
                    'Title / Reason',
                    'Type',
                    'Mode',
                    'Amount',
                    'Note'
                  ].map((v) {
                    return pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(v,
                          style: pw.TextStyle(
                              fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    );
                  }).toList(),
                ),
                ...list.map(
                  (item) => pw.TableRow(
                    children: [
                      '${item.dateTime.day.toString().padLeft(2, '0')}/${item.dateTime.month.toString().padLeft(2, '0')}/${item.dateTime.year}',
                      item.title,
                      item.type.shortLabel,
                      item.paymentMode.label,
                      '${item.type == InvestmentType.credit ? '+' : '-'} ${money(item.amount)}',
                      item.note.isEmpty ? '-' : item.note,
                    ].map((val) {
                      return pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(val,
                            style: const pw.TextStyle(fontSize: 8.5)),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    final bytes = await doc.save();
    final safePeriod = _periodLabel.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'investment_statement_${safePeriod.toLowerCase()}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _filteredInvestments;
    final primary = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(
          title: 'Investments',
          subtitle: 'Manage Credit (Invest) & Debit independently.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: widget.onAddInvestment,
          icon: const Icon(Icons.add_card_rounded),
          label: const Text('Add Investment / Debit Entry'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.all(16),
            backgroundColor: const Color(0xff059669),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: ['Daily', 'Monthly', 'Yearly', 'All Time']
                .asMap()
                .entries
                .map((e) {
              final selected = _filterIndex == e.key;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _filterIndex = e.key;
                    _selectedDate = DateTime.now();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      e.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color:
                            selected ? Colors.white : _mutedTextColor(context),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        if (_filterIndex != 3)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _cardColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isDarkMode(context)
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade200,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _goBack,
                  color: primary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                Text(
                  _periodLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _goForward,
                  color: primary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        SegmentedButton<InvestmentType?>(
          segments: const [
            ButtonSegment(
              value: null,
              icon: Icon(Icons.swap_horiz_rounded),
              label: Text('All'),
            ),
            ButtonSegment(
              value: InvestmentType.credit,
              icon: Icon(Icons.south_west_rounded, color: Color(0xff059669)),
              label: Text('Credit (Invest)'),
            ),
            ButtonSegment(
              value: InvestmentType.debit,
              icon: Icon(Icons.north_east_rounded, color: Color(0xffdc2626)),
              label: Text('Debit'),
            ),
          ],
          selected: {_typeFilter},
          onSelectionChanged: (selection) =>
              setState(() => _typeFilter = selection.first),
        ),
        const SizedBox(height: 10),
        SegmentedButton<PaymentMode?>(
          segments: const [
            ButtonSegment(
              value: null,
              icon: Icon(Icons.receipt_long_outlined),
              label: Text('All Modes'),
            ),
            ButtonSegment(
              value: PaymentMode.cash,
              icon: Icon(Icons.payments_outlined),
              label: Text('Cash'),
            ),
            ButtonSegment(
              value: PaymentMode.online,
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: Text('Online'),
            ),
          ],
          selected: {_paymentFilter},
          onSelectionChanged: (selection) =>
              setState(() => _paymentFilter = selection.first),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _exportInvestmentPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Export Statement PDF'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xff6366f1),
          ),
        ),
        const SizedBox(height: 16),
        _MetricGrid(
          metrics: [
            _Metric(
              'Total Invested',
              money(_totalCredit),
              Icons.trending_up_rounded,
              const Color(0xff059669),
            ),
            _Metric(
              'Total Debited',
              money(_totalDebit),
              Icons.trending_down_rounded,
              const Color(0xffdc2626),
            ),
            _Metric(
              'Net Balance',
              money(_netBalance),
              Icons.account_balance_wallet_rounded,
              _netBalance >= 0
                  ? const Color(0xff2563eb)
                  : const Color(0xffdc2626),
            ),
            _Metric(
              'Entries',
              sorted.length.toString(),
              Icons.receipt_long_outlined,
              const Color(0xff7c3aed),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const _SectionTitle('Investment History'),
            const Spacer(),
            Text(
              '${sorted.length} transaction${sorted.length == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'No investment or debit transactions found.',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          )
        else
          ...sorted.map(
            (item) => _InvestmentTile(
              transaction: item,
              onEdit: () => widget.onEditInvestment(item),
              onDelete: () => widget.onDeleteInvestment(item),
            ),
          ),
      ],
    );
  }
}

class _InvestmentTile extends StatelessWidget {
  const _InvestmentTile({
    required this.transaction,
    required this.onEdit,
    required this.onDelete,
  });

  final InvestmentTransaction transaction;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.type == InvestmentType.credit;
    final badgeColor =
        isCredit ? const Color(0xff059669) : const Color(0xffdc2626);
    final date =
        '${transaction.dateTime.day.toString().padLeft(2, '0')}/${transaction.dateTime.month.toString().padLeft(2, '0')}/${transaction.dateTime.year}';
    final time = TimeOfDay.fromDateTime(transaction.dateTime).format(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isDarkMode(context)
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: _softShadowColor(context),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isCredit
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  color: badgeColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            transaction.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          '${isCredit ? '+' : '-'} ${money(transaction.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: badgeColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            transaction.type.label,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$date $time • ${transaction.paymentMode.label}',
                          style: TextStyle(
                            color: _mutedTextColor(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (transaction.note.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Note: ${transaction.note.trim()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _mutedTextColor(context),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Edit transaction',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: onEdit,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          tooltip: 'Delete transaction',
                          icon: const Icon(Icons.delete_outline),
                          color: Colors.red,
                          onPressed: onDelete,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportsPage extends StatefulWidget {
  const _ReportsPage({
    required this.customers,
    required this.bills,
    required this.appointments,
    required this.onShareBill,
    required this.onExportBill,
  });

  final List<Customer> customers;
  final List<Bill> bills;
  final List<Appointment> appointments;
  final ValueChanged<Bill> onShareBill;
  final ValueChanged<Bill> onExportBill;

  @override
  State<_ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<_ReportsPage> {
  // 0 = Daily, 1 = Monthly, 2 = Yearly
  int _filterIndex = 3; // default: All Time
  PaymentMode? _paymentFilter;

  // For daily: selected date; for monthly: selected month+year; for yearly: selected year
  DateTime _selectedDate = DateTime.now();

  List<Bill> get _filteredBills {
    final now = _selectedDate;
    return widget.bills.where((bill) {
      if (_paymentFilter != null && bill.paymentMode != _paymentFilter) {
        return false;
      }

      switch (_filterIndex) {
        case 0: // Daily
          return bill.date.year == now.year &&
              bill.date.month == now.month &&
              bill.date.day == now.day;
        case 1: // Monthly
          return bill.date.year == now.year && bill.date.month == now.month;
        case 2: // Yearly
          return bill.date.year == now.year;
        case 3: // All Time
          return true;
        default:
          return true;
      }
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  double get _filteredSales =>
      _filteredBills.fold(0.0, (sum, b) => sum + b.total);

  int get _filteredBillCount => _filteredBills.length;

  /// Returns customers sorted by total spend in the current period, highest first.
  List<MapEntry<String, double>> get _topCustomers {
    final totals = <String, double>{};
    for (final bill in _filteredBills) {
      totals[bill.customerName] = (totals[bill.customerName] ?? 0) + bill.total;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }

  Map<String, double> get _serviceTotals {
    final totals = <String, double>{};
    for (final bill in _filteredBills) {
      if (bill.services.isEmpty) continue;
      final fallbackPrice = bill.total / bill.services.length;
      for (final service in bill.services) {
        final price = bill.servicePrices[service] ?? fallbackPrice;
        totals[service] = (totals[service] ?? 0) + price;
      }
    }
    return totals;
  }

  String get _periodLabel {
    final d = _selectedDate;
    switch (_filterIndex) {
      case 0:
        return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      case 1:
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        return '${months[d.month - 1]} ${d.year}';
      case 2:
        return '${d.year}';
      case 3:
        return 'All Time';
      default:
        return '';
    }
  }

  void _goBack() {
    if (_filterIndex == 3) return;
    setState(() {
      switch (_filterIndex) {
        case 0:
          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
          break;
        case 1:
          _selectedDate = DateTime(
              _selectedDate.month == 1
                  ? _selectedDate.year - 1
                  : _selectedDate.year,
              _selectedDate.month == 1 ? 12 : _selectedDate.month - 1);
          break;
        case 2:
          _selectedDate = DateTime(_selectedDate.year - 1);
          break;
      }
    });
  }

  void _goForward() {
    if (_filterIndex == 3) return;
    final now = DateTime.now();
    setState(() {
      switch (_filterIndex) {
        case 0:
          final next = _selectedDate.add(const Duration(days: 1));
          if (!next.isAfter(now)) _selectedDate = next;
          break;
        case 1:
          final nextMonth = _selectedDate.month == 12
              ? DateTime(_selectedDate.year + 1, 1)
              : DateTime(_selectedDate.year, _selectedDate.month + 1);
          if (!nextMonth.isAfter(now)) _selectedDate = nextMonth;
          break;
        case 2:
          if (_selectedDate.year < now.year) {
            _selectedDate = DateTime(_selectedDate.year + 1);
          }
          break;
      }
    });
  }

  Future<void> _exportStatementPdf() async {
    final bytes = await _buildStatementPdf(
      bills: _filteredBills,
      serviceTotals: _serviceTotals,
      periodLabel: _periodLabel,
      totalSales: _filteredSales,
      periodType: switch (_filterIndex) {
        0 => 'Daily',
        1 => 'Monthly',
        2 => 'Yearly',
        _ => 'All Time',
      },
      paymentLabel: _paymentFilter?.label ?? 'All',
    );
    final safePeriod = _periodLabel.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final fileName = 'statement_${safePeriod.toLowerCase()}.pdf';

    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  Future<Uint8List> _buildStatementPdf({
    required List<Bill> bills,
    required Map<String, double> serviceTotals,
    required String periodLabel,
    required double totalSales,
    required String periodType,
    required String paymentLabel,
  }) async {
    final sortedServiceTotals = serviceTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            '$periodType Statement',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Period: $periodLabel'),
          pw.Text('Payment: $paymentLabel'),
          pw.SizedBox(height: 14),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Bills: ${bills.length}'),
              pw.Text(
                'Total Sales: ${money(totalSales)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.Divider(height: 24),
          pw.Text(
            'Transactions',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15),
          ),
          pw.SizedBox(height: 8),
          if (bills.isEmpty)
            pw.Text('No statement entries for this period.')
          else
            pw.Table(
              border: pw.TableBorder.all(width: 0.4),
              columnWidths: const {
                0: pw.FixedColumnWidth(48),
                1: pw.FixedColumnWidth(58),
                2: pw.FlexColumnWidth(1.1),
                3: pw.FlexColumnWidth(1.5),
                4: pw.FixedColumnWidth(52),
                5: pw.FixedColumnWidth(62),
              },
              children: [
                _statementPdfRow(
                  ['Date', 'Bill', 'Customer', 'Services', 'Mode', 'Amount'],
                  isHeader: true,
                ),
                ...bills.map(
                  (bill) => _statementPdfRow([
                    _pdfShortDate(bill.date),
                    bill.id,
                    bill.customerName,
                    bill.services.isEmpty ? '-' : bill.services.join(', '),
                    bill.paymentMode.label,
                    money(bill.total),
                  ]),
                ),
              ],
            ),
          if (sortedServiceTotals.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Service-wise Total',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(width: 0.4),
              columnWidths: const {
                0: pw.FlexColumnWidth(),
                1: pw.FixedColumnWidth(80),
              },
              children: [
                _statementPdfRow(['Service', 'Total'], isHeader: true),
                ...sortedServiceTotals.map(
                  (entry) => _statementPdfRow([entry.key, money(entry.value)]),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  pw.TableRow _statementPdfRow(List<String> values, {bool isHeader = false}) {
    return pw.TableRow(
      decoration: isHeader
          ? const pw.BoxDecoration(color: PdfColor.fromInt(0xffeeeeee))
          : null,
      children: values.map((value) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _pdfShortDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredBills;
    final primary = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(
            title: 'Reports', subtitle: 'Filter sales by day, month, or year.'),
        const SizedBox(height: 16),

        // ── Filter tabs ──────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: ['Daily', 'Monthly', 'Yearly', 'All Time'].asMap().entries.map((e) {
              final selected = _filterIndex == e.key;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _filterIndex = e.key;
                    _selectedDate = DateTime.now();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      e.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color:
                            selected ? Colors.white : _mutedTextColor(context),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // ── Period navigator ─────────────────────────────────────────────
        if (_filterIndex != 3)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _cardColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isDarkMode(context)
                  ? Colors.white.withOpacity(0.08)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _goBack,
                color: primary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                _periodLabel,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _goForward,
                color: primary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Summary cards ────────────────────────────────────────────────
        SegmentedButton<PaymentMode?>(
          segments: const [
            ButtonSegment(
              value: null,
              icon: Icon(Icons.receipt_long_outlined),
              label: Text('All'),
            ),
            ButtonSegment(
              value: PaymentMode.cash,
              icon: Icon(Icons.payments_outlined),
              label: Text('Cash'),
            ),
            ButtonSegment(
              value: PaymentMode.online,
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: Text('Online'),
            ),
          ],
          selected: {_paymentFilter},
          onSelectionChanged: (selection) =>
              setState(() => _paymentFilter = selection.first),
        ),
        const SizedBox(height: 16),

        _MetricGrid(
          metrics: [
            _Metric(
              'Total Sales',
              money(_filteredSales),
              Icons.trending_up,
              const Color(0xff0f766e),
            ),
            _Metric(
              'Total Bills',
              _filteredBillCount.toString(),
              Icons.receipt_long_outlined,
              const Color(0xff7c3aed),
            ),
          ],
        ),
        const SizedBox(height: 24),

        _StatementSection(
          bills: filtered,
          serviceTotals: _serviceTotals,
          periodLabel: _periodLabel,
          totalSales: _filteredSales,
          onExportPdf: _exportStatementPdf,
        ),
        const SizedBox(height: 24),

        // ── Top customers (Monthly / Yearly only) ────────────────────────
        if (_filterIndex != 0 && _topCustomers.isNotEmpty) ...[
          _TopCustomersSection(
            topCustomers: _topCustomers,
            periodLabel: _periodLabel,
          ),
          const SizedBox(height: 24),
        ],

        // ── Bills list ───────────────────────────────────────────────────
        Row(
          children: [
            const _SectionTitle('Bills'),
            const Spacer(),
            Text(
              '${filtered.length} bill${filtered.length == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'No bills for $_periodLabel',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          )
        else
          ...filtered.map(
            (bill) => _BillTileV2(
              bill: bill,
              onShare: () => widget.onShareBill(bill),
              onExportPdf: () => widget.onExportBill(bill),
            ),
          ),
      ],
    );
  }
}

class _StatementSection extends StatelessWidget {
  const _StatementSection({
    required this.bills,
    required this.serviceTotals,
    required this.periodLabel,
    required this.totalSales,
    required this.onExportPdf,
  });

  final List<Bill> bills;
  final Map<String, double> serviceTotals;
  final String periodLabel;
  final double totalSales;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    final sortedServiceTotals = serviceTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionTitle('Statement'),
            const Spacer(),
            Text(
              periodLabel,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isDarkMode(context)
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade200,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.summarize_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${bills.length} transaction${bills.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    money(totalSales),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onExportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Export PDF'),
                ),
              ),
              const SizedBox(height: 12),
              if (bills.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No statement entries for this period.',
                    style: TextStyle(color: _mutedTextColor(context)),
                  ),
                )
              else ...[
                ...bills.map((bill) => _StatementBillRow(bill: bill)),
                if (sortedServiceTotals.isNotEmpty) ...[
                  const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Service-wise total',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...sortedServiceTotals.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            money(entry.value),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatementBillRow extends StatelessWidget {
  const _StatementBillRow({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final services =
        bill.services.isEmpty ? 'No services' : bill.services.join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              _shortDate(bill.date),
              style: TextStyle(
                color: _mutedTextColor(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  services,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _mutedTextColor(context),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${bill.id} • ${bill.paymentMode.label}',
                  style: TextStyle(
                    color: _mutedTextColor(context),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            money(bill.total),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  String _shortDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}

// ── Top Customers Section ─────────────────────────────────────────────────────

class _TopCustomersSection extends StatelessWidget {
  final List<MapEntry<String, double>> topCustomers;
  final String periodLabel;

  const _TopCustomersSection({
    required this.topCustomers,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final top = topCustomers.first;
    final showFull = topCustomers.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionTitle('Top Customers'),
            const Spacer(),
            Text(
              periodLabel,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── #1 Highlighted card ──────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primary.withValues(alpha: 0.15),
                primary.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    top.key.isNotEmpty ? top.key[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.emoji_events,
                            color: Color(0xfff59e0b), size: 16),
                        const SizedBox(width: 4),
                        const Text(
                          'Highest Spender',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xfff59e0b),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      top.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                money(top.value),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: primary,
                ),
              ),
            ],
          ),
        ),

        // ── Remaining top customers (up to rank 5) ───────────────────────
        if (showFull) ...[
          const SizedBox(height: 8),
          ...topCustomers.skip(1).take(4).toList().asMap().entries.map((e) {
            final rank = e.key + 2; // starts at 2
            final name = e.value.key;
            final total = e.value.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _cardColor(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDarkMode(context)
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: primary.withValues(alpha: 0.12),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                          fontSize: 12,
                          color: primary,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    money(total),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.settings,
    required this.onSave,
    required this.onConnectGoogle,
    required this.onBackup,
    required this.onRestore,
    required this.onShareLocalBackup,
    required this.onImportLocalBackup,
    required this.onCleanPhoneFromNotes,
  });

  final _ShopSettings settings;
  final Future<void> Function(_ShopSettings settings) onSave;
  final Future<String> Function() onConnectGoogle;
  final Future<String> Function() onBackup;
  final Future<String> Function() onRestore;
  final Future<String> Function() onShareLocalBackup;
  final Future<String> Function() onImportLocalBackup;
  final Future<int> Function() onCleanPhoneFromNotes;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController _parlourController;
  late final TextEditingController _ownerController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _openingController;
  late final TextEditingController _closingController;
  late final TextEditingController _backupEmailController;
  late final TextEditingController _footerController;
  late final TextEditingController _greenApiUrlController;
  late final TextEditingController _greenApiInstanceController;
  late final TextEditingController _greenApiTokenController;
  late bool _bookingReminderEnabled;
  late int _reminderMinutes;
  late bool _autoBackupEnabled;
  late bool _darkModeEnabled;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _parlourController =
        TextEditingController(text: widget.settings.parlourName);
    _ownerController = TextEditingController(text: widget.settings.ownerName);
    _phoneController = TextEditingController(text: widget.settings.shopPhone);
    _addressController =
        TextEditingController(text: widget.settings.shopAddress);
    _openingController =
        TextEditingController(text: widget.settings.openingTime);
    _closingController =
        TextEditingController(text: widget.settings.closingTime);
    _backupEmailController =
        TextEditingController(text: widget.settings.backupEmail);
    _footerController =
        TextEditingController(text: widget.settings.invoiceFooter);
    _greenApiUrlController =
        TextEditingController(text: widget.settings.greenApiUrl);
    _greenApiInstanceController =
        TextEditingController(text: widget.settings.greenApiInstanceId);
    _greenApiTokenController =
        TextEditingController(text: widget.settings.greenApiToken);
    _bookingReminderEnabled = widget.settings.bookingReminderEnabled;
    _reminderMinutes = widget.settings.reminderMinutes;
    _autoBackupEnabled = widget.settings.autoBackupEnabled;
    _darkModeEnabled = widget.settings.darkModeEnabled;
  }

  @override
  void dispose() {
    _parlourController.dispose();
    _ownerController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _openingController.dispose();
    _closingController.dispose();
    _backupEmailController.dispose();
    _footerController.dispose();
    _greenApiUrlController.dispose();
    _greenApiInstanceController.dispose();
    _greenApiTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final googleDriveConfigured = _googleSignInServerClientId.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(title: 'Settings', subtitle: 'Manage shop preferences.'),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Shop Details',
          icon: Icons.storefront_outlined,
          children: [
            TextField(
              controller: _parlourController,
              decoration: const InputDecoration(labelText: 'Parlour name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ownerController,
              decoration: const InputDecoration(labelText: 'Owner name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Shop phone'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Shop address'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Display',
          icon: Icons.dark_mode_outlined,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dark mode'),
              subtitle: const Text('Use dark colors throughout the app'),
              value: _darkModeEnabled,
              onChanged: (value) {
                setState(() => _darkModeEnabled = value);
                appThemeMode.value = value ? ThemeMode.dark : ThemeMode.light;
                unawaited(_saveSettings(showMessage: false));
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Business Hours',
          icon: Icons.schedule_outlined,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _openingController,
                    decoration: const InputDecoration(labelText: 'Open time'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _closingController,
                    decoration: const InputDecoration(labelText: 'Close time'),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Bookings',
          icon: Icons.notifications_active_outlined,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Booking notification'),
              subtitle: const Text('Show reminder when booking time comes'),
              value: _bookingReminderEnabled,
              onChanged: (value) =>
                  setState(() => _bookingReminderEnabled = value),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _reminderMinutes,
              decoration: const InputDecoration(labelText: 'Reminder before'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('At booking time')),
                DropdownMenuItem(value: 5, child: Text('5 minutes before')),
                DropdownMenuItem(value: 10, child: Text('10 minutes before')),
                DropdownMenuItem(value: 15, child: Text('15 minutes before')),
                DropdownMenuItem(value: 30, child: Text('30 minutes before')),
                DropdownMenuItem(value: 60, child: Text('1 hour before')),
              ],
              onChanged: _bookingReminderEnabled
                  ? (value) => setState(() => _reminderMinutes = value ?? 0)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'WhatsApp Poll',
          icon: Icons.poll_outlined,
          children: [
            Text(
              'Add Green API details to send native WhatsApp confirmation polls.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _greenApiUrlController,
              decoration: const InputDecoration(
                labelText: 'Green API URL',
                hintText: 'https://api.green-api.com',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _greenApiInstanceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'idInstance'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _greenApiTokenController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'apiTokenInstance'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Bills',
          icon: Icons.receipt_long_outlined,
          children: [
            TextField(
              controller: _footerController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'PDF bill footer'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Backup',
          icon: Icons.cloud_done_outlined,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto Google backup'),
              subtitle: Text(
                googleDriveConfigured
                    ? 'Backup changes automatically when possible'
                    : 'Google setup is required before backup can run',
              ),
              value: _autoBackupEnabled,
              onChanged: googleDriveConfigured
                  ? (value) => setState(() => _autoBackupEnabled = value)
                  : null,
            ),
            TextField(
              controller: _backupEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Backup Gmail'),
            ),
            const SizedBox(height: 12),
            Text(
              googleDriveConfigured
                  ? 'Google backup stores data privately in the selected Gmail Drive app data.'
                  : 'Add a Google Web client ID, then rebuild the APK. Local phone data still saves on this device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  _syncing ? null : () => _runSync(widget.onShareLocalBackup),
              icon: const Icon(Icons.ios_share_outlined),
              label: Text(_syncing ? 'Please wait...' : 'Share Data Backup'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  _syncing ? null : () => _runSync(widget.onImportLocalBackup),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Import Data Backup'),
            ),
            const SizedBox(height: 12),
            Text(
              'Use the same backup Gmail on every phone to move your app data.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  _syncing ? null : () => _runSync(widget.onConnectGoogle),
              icon: const Icon(Icons.account_circle_outlined),
              label: Text(_syncing ? 'Please wait...' : 'Login with Gmail'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _syncing ? null : () => _runSync(widget.onBackup),
              icon: const Icon(Icons.cloud_upload_outlined),
              label:
                  Text(_syncing ? 'Please wait...' : 'Backup to Google Drive'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _syncing ? null : () => _runSync(widget.onRestore),
              icon: const Icon(Icons.login_outlined),
              label: const Text('Login with Google & Restore Data'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // ── Data cleanup ─────────────────────────────────────────────
        OutlinedButton.icon(
          onPressed: _syncing ? null : _runCleanPhoneFromNotes,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('Fix Notes: Remove Phone Numbers'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange.shade700,
            side: BorderSide(color: Colors.orange.shade300),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saveSettings,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Settings'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  _ShopSettings _currentSettings() {
    return _ShopSettings(
      parlourName: _parlourController.text.trim().isEmpty
          ? 'Nupur Beauty Parlour'
          : _parlourController.text.trim(),
      ownerName: _ownerController.text.trim(),
      shopPhone: _phoneController.text.trim(),
      shopAddress: _addressController.text.trim(),
      openingTime: _openingController.text.trim(),
      closingTime: _closingController.text.trim(),
      bookingReminderEnabled: _bookingReminderEnabled,
      reminderMinutes: _reminderMinutes,
      autoBackupEnabled: _autoBackupEnabled,
      backupEmail: _backupEmailController.text.trim().isEmpty
          ? _ParlourHomeState._defaultBackupEmail
          : _backupEmailController.text.trim(),
      invoiceFooter: _footerController.text.trim(),
      darkModeEnabled: _darkModeEnabled,
      greenApiUrl: _greenApiUrlController.text.trim().isEmpty
          ? 'https://api.green-api.com'
          : _greenApiUrlController.text.trim(),
      greenApiInstanceId: _greenApiInstanceController.text.trim(),
      greenApiToken: _greenApiTokenController.text.trim(),
    );
  }

  Future<void> _saveSettings({bool showMessage = true}) async {
    await widget.onSave(_currentSettings());
    if (!mounted) return;
    if (showMessage) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _runCleanPhoneFromNotes() async {
    setState(() => _syncing = true);
    try {
      final count = await widget.onCleanPhoneFromNotes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count == 0
              ? 'No phone numbers found in notes'
              : 'Cleaned $count client note${count == 1 ? '' : 's'}'),
          backgroundColor: count == 0 ? null : Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _runSync(Future<String> Function() action) async {
    setState(() => _syncing = true);
    try {
      await _saveSettings(showMessage: false);
      final message = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _friendlyBackupError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (message.contains('GoogleSignInExceptionCode.canceled') ||
        message.contains('Account reauth failed')) {
      return 'Google login was cancelled or expired. Tap Backup to Google Drive again, choose the backup Gmail, and allow Drive permission.';
    }
    if (message.contains('clientConfigurationError') ||
        message.contains('providerConfigurationError') ||
        message.contains('ApiException: 10')) {
      return 'Google backup is not configured correctly. Rebuild the APK with the correct Google Web Client ID and Android SHA-1 setup.';
    }
    return message;
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.25)
                : Colors.black.withOpacity(0.03),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _DriveSession {
  const _DriveSession({
    required this.email,
    required this.driveApi,
  });

  final String email;
  final drive.DriveApi driveApi;
}

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

bool _isDarkMode(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _cardColor(BuildContext context) => Theme.of(context).colorScheme.surface;

Color _mutedTextColor(BuildContext context) =>
    _isDarkMode(context) ? Colors.grey.shade400 : Colors.grey.shade600;

Color _softShadowColor(BuildContext context, [Color? tint]) =>
    _isDarkMode(context)
        ? Colors.black.withOpacity(0.28)
        : (tint ?? Colors.black).withOpacity(0.04);

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: textTheme.headlineMedium?.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                color: _mutedTextColor(context),
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _DashboardDateRangeFilter extends StatelessWidget {
  const _DashboardDateRangeFilter({
    required this.start,
    required this.end,
    required this.onTap,
  });

  final DateTime start;
  final DateTime end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Date Range:',
              style: TextStyle(
                color: _mutedTextColor(context),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isDarkMode(context)
                    ? Colors.white.withOpacity(0.06)
                    : const Color(0xffF3F4F6),
                border: Border.all(
                  color: _isDarkMode(context)
                      ? Colors.white.withOpacity(0.14)
                      : const Color(0xffD1D5DB),
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '${_shortDate(start)} ~ ${_shortDate(end)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: _mutedTextColor(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.3,
      ),
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return Material(
          color: _cardColor(context),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: metric.onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: _isDarkMode(context)
                          ? Colors.black.withOpacity(0.25)
                          : metric.color.withOpacity(0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            metric.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _mutedTextColor(context),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: metric.color.withOpacity(0.1),
                              shape: BoxShape.circle),
                          child:
                              Icon(metric.icon, color: metric.color, size: 20),
                        ),
                      ],
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        metric.value,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w800));
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({
    required this.customer,
    required this.bills,
    required this.appointments,
    required this.onEdit,
    required this.onDelete,
    required this.onUpdated,
    this.onAddBill,
  });

  final Customer customer;
  final List<Bill> bills;
  final List<Appointment> appointments;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<void> Function(Customer customer) onUpdated;
  final void Function(Customer customer)? onAddBill;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: _softShadowColor(context),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: ListTile(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => _CustomerDetailsPage(
                      customer: customer,
                      bills: bills,
                      appointments: appointments,
                      onUpdated: onUpdated,
                      onAddBill: onAddBill != null
                          ? () => onAddBill!(customer)
                          : null))),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor:
                Theme.of(context).colorScheme.primary.withOpacity(0.1),
            child: Text(
                customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          title: Text(customer.name,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: Text(
              '${customer.phone} • ${customer.note}${customer.referredBy.isNotEmpty ? '\nReferred by: ${customer.referredBy}' : ''}',
              style: TextStyle(height: 1.4, color: _mutedTextColor(context))),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Edit client',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Delete client',
                icon: const Icon(Icons.delete_outline),
                color: Colors.red,
                onPressed: onDelete,
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.green.shade50, shape: BoxShape.circle),
                  child:
                      Icon(Icons.call, color: Colors.green.shade700, size: 20),
                ),
                onPressed: () async {
                  final url = Uri.parse('tel:${customer.phone}');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({
    required this.appointment,
    this.onEdit,
    this.onConfirm,
    this.onArrived,
    this.onDelete,
  });

  final Appointment appointment;
  final VoidCallback? onEdit;
  final VoidCallback? onConfirm;
  final VoidCallback? onArrived;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isArrived = appointment.status == 'Arrived';
    final isConfirmed = appointment.status == 'Confirmed';
    final isPending = appointment.status == 'Pending';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: _softShadowColor(context),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xff3B82F6).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.event_available_rounded,
                    color: Color(0xff3B82F6)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.customerName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appointment.serviceName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          height: 1.35, color: _mutedTextColor(context)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${appointment.date.day.toString().padLeft(2, '0')}/${appointment.date.month.toString().padLeft(2, '0')}/${appointment.date.year} * ${appointment.time.format(context)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          height: 1.35, color: _mutedTextColor(context)),
                    ),
                    const SizedBox(height: 10),
                    Chip(
                      label: Text(appointment.status,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12)),
                      backgroundColor: isArrived
                          ? const Color(0xffDBEAFE)
                          : isConfirmed
                              ? const Color(0xffD1FAE5)
                              : const Color(0xffFEF3C7),
                      labelStyle: TextStyle(
                          color: isArrived
                              ? const Color(0xff2563EB)
                              : isConfirmed
                                  ? const Color(0xff059669)
                                  : const Color(0xffD97706)),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (onArrived != null && !isArrived)
                          OutlinedButton.icon(
                            onPressed: onArrived,
                            icon: const Icon(Icons.person_pin_circle_outlined,
                                size: 18),
                            label: const Text('Arrived'),
                          ),
                        if (onConfirm != null && isPending)
                          OutlinedButton.icon(
                            onPressed: onConfirm,
                            icon: const Icon(Icons.check_circle_outline,
                                size: 18),
                            label: const Text('Confirm'),
                          ),
                        if (onEdit != null)
                          OutlinedButton.icon(
                            onPressed: onEdit,
                            icon: const Icon(Icons.event_repeat, size: 18),
                            label: const Text('Reschedule'),
                          ),
                        if (onDelete != null)
                          OutlinedButton.icon(
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Delete'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.onEdit,
    required this.onDelete,
  });

  final ParlourService service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.spa_outlined),
          title: Text(service.name),
          subtitle: Text('${service.durationMinutes} min'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(money(service.price),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Edit service',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Delete service',
                icon: const Icon(Icons.delete_outline),
                color: Colors.red,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillTileV2 extends StatelessWidget {
  const _BillTileV2({
    required this.bill,
    this.onEdit,
    this.onDelete,
    this.onShare,
    this.onExportPdf,
  });

  final Bill bill;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final VoidCallback? onExportPdf;

  @override
  Widget build(BuildContext context) {
    final title =
        '${bill.id} - ${bill.customerName} (${bill.paymentMode.label})';
    final date =
        '${bill.date.day.toString().padLeft(2, '0')}/${bill.date.month.toString().padLeft(2, '0')}/${bill.date.year}';
    final subtitle = '$date | ${bill.services.join(', ')}';
    final hasActions = onExportPdf != null ||
        onShare != null ||
        onEdit != null ||
        onDelete != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.receipt_long_outlined),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          money(bill.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _mutedTextColor(context)),
                    ),
                    if (hasActions) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (onExportPdf != null)
                            IconButton(
                              tooltip: 'Export bill PDF',
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              color: Colors.red,
                              onPressed: onExportPdf,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (onShare != null)
                            IconButton(
                              tooltip: 'Send bill PDF',
                              icon: const Icon(Icons.share_outlined),
                              color: Colors.red,
                              onPressed: onShare,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (onEdit != null)
                            IconButton(
                              tooltip: 'Edit bill',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: onEdit,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (onDelete != null)
                            IconButton(
                              tooltip: 'Delete bill',
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.red,
                              onPressed: onDelete,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({
    required this.bill,
    this.onEdit,
    this.onDelete,
    this.onShare,
    this.onExportPdf,
  });

  final Bill bill;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final VoidCallback? onExportPdf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(
              '${bill.id} - ${bill.customerName} (${bill.paymentMode.label})'),
          subtitle: Text(
              '${bill.date.day.toString().padLeft(2, '0')}/${bill.date.month.toString().padLeft(2, '0')}/${bill.date.year} • ${bill.services.join(', ')}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(money(bill.total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              if (onExportPdf != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Export bill PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  color: Colors.red,
                  onPressed: onExportPdf,
                ),
              ],
              if (onShare != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Send bill PDF',
                  icon: const Icon(Icons.share_outlined),
                  color: Colors.red,
                  onPressed: onShare,
                ),
              ],
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Edit bill',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
              ],
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Delete bill',
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({this.customer});

  final Customer? customer;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _note;
  late final TextEditingController _referredBy;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _name = TextEditingController(text: customer?.name ?? '');
    _phone = TextEditingController(text: customer?.phone ?? '');
    _note = TextEditingController(text: customer?.note ?? '');
    _referredBy = TextEditingController(text: customer?.referredBy ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    _referredBy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight - viewInsets.bottom - 48,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.customer == null ? 'Add Customer' : 'Edit Customer',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words),
              const SizedBox(height: 8),
              TextField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 8),
              TextField(
                  controller: _referredBy,
                  decoration: const InputDecoration(
                      labelText: 'Referred By (Optional)')),
              const SizedBox(height: 8),
              TextField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  minLines: 1,
                  maxLines: 3),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (_name.text.trim().isEmpty) return;
                      Navigator.pop(
                        context,
                        Customer(
                            widget.customer?.id ??
                                DateTime.now()
                                    .millisecondsSinceEpoch
                                    .toString(),
                            _name.text.trim(),
                            _phone.text.trim(),
                            _note.text.trim(),
                            referredBy: _referredBy.text.trim()),
                      );
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog({this.service});

  final ParlourService? service;

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _price;
  late final TextEditingController _duration;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _name = TextEditingController(text: service?.name ?? '');
    _category = TextEditingController(text: service?.category ?? 'Beauty');
    _price = TextEditingController(
        text: service == null ? '' : service.price.toStringAsFixed(0));
    _duration =
        TextEditingController(text: '${service?.durationMinutes ?? 30}');
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _price.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.service == null ? 'Add Service' : 'Edit Service'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Service name')),
          const SizedBox(height: 8),
          TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Category')),
          const SizedBox(height: 8),
          TextField(
              controller: _price,
              decoration: const InputDecoration(labelText: 'Price'),
              keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          TextField(
              controller: _duration,
              decoration: const InputDecoration(labelText: 'Minutes'),
              keyboardType: TextInputType.number),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              ParlourService(
                _name.text.trim(),
                _category.text.trim().isEmpty
                    ? 'Beauty'
                    : _category.text.trim(),
                double.tryParse(_price.text) ?? 0,
                int.tryParse(_duration.text) ?? 30,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _AppointmentDialog extends StatefulWidget {
  const _AppointmentDialog({
    required this.customers,
    required this.services,
    this.appointment,
    this.initialDate,
  });

  final List<Customer> customers;
  final List<ParlourService> services;
  final Appointment? appointment;
  final DateTime? initialDate;

  @override
  State<_AppointmentDialog> createState() => _AppointmentDialogState();
}

class _AppointmentDialogState extends State<_AppointmentDialog> {
  Customer? _customer;
  late TextEditingController _customerController;
  final List<ParlourService> _selectedServices = [];
  DateTime _date = DateTime.now();
  TimeOfDay? _time;
  List<Customer> _filteredCustomers = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    final appointment = widget.appointment;
    String initialName = '';
    if (appointment != null && widget.customers.isNotEmpty) {
      _customer = widget.customers.firstWhere(
        (customer) => customer.name == appointment.customerName,
        orElse: () => widget.customers.first,
      );
      initialName = _customer?.name ?? appointment.customerName;
      final selectedNames = appointment.serviceName
          .split(',')
          .map((name) => name.trim().toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();
      _selectedServices.addAll(
        widget.services.where(
          (service) => selectedNames.contains(service.name.toLowerCase()),
        ),
      );
    }
    _customerController = TextEditingController(text: initialName);
    _date = appointment?.date ?? widget.initialDate ?? DateTime.now();
    _time = appointment?.time;
  }

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  void _onCustomerTextChanged(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _customer = null;
      if (query.isEmpty) {
        _filteredCustomers = [];
        _showSuggestions = false;
      } else {
        _filteredCustomers = widget.customers
            .where((c) =>
                c.name.toLowerCase().contains(query) ||
                c.phone.replaceAll(RegExp(r'\D'), '').contains(query))
            .take(6)
            .toList();
        _showSuggestions = _filteredCustomers.isNotEmpty;
      }
    });
  }

  String get _customerName => _customerController.text.trim();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      scrollable: true,
      title: Text(
          widget.appointment == null ? 'New Appointment' : 'Edit Appointment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Customer field: type or select ──────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _customerController,
                decoration: const InputDecoration(
                  labelText: 'Customer',
                  hintText: 'Type or select customer',
                  suffixIcon: Icon(Icons.person_search_outlined),
                ),
                onChanged: _onCustomerTextChanged,
                onTap: () {
                  if (_customerController.text.trim().isNotEmpty) {
                    _onCustomerTextChanged(_customerController.text);
                  }
                },
              ),
              if (_showSuggestions && _filteredCustomers.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final c in _filteredCustomers)
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                            child: Text(
                              c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: c.phone.isNotEmpty
                              ? Text(c.phone, style: const TextStyle(fontSize: 11))
                              : null,
                          onTap: () {
                            setState(() {
                              _customer = c;
                              _customerController.text = c.name;
                              _showSuggestions = false;
                              _filteredCustomers = [];
                            });
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickServices,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Services',
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                _selectedServices.isEmpty
                    ? 'Select services'
                    : _selectedServices
                        .map((service) => service.name)
                        .join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _selectedServices.isEmpty
                      ? _mutedTextColor(context)
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                softWrap: false,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 365)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)));
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${_date.day}/${_date.month}/${_date.year}'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () async {
                    final picked = await showTimePicker(
                        context: context,
                        initialTime: _time ?? TimeOfDay.now());
                    if (picked != null) setState(() => _time = picked);
                  },
                  icon: const Icon(Icons.schedule, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_time?.format(context) ?? 'Select time'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _customerName.isEmpty ||
                  _selectedServices.isEmpty ||
                  _time == null
              ? null
              : () => Navigator.pop(
                  context,
                  Appointment(
                      _customerName,
                      _selectedServices
                          .map((service) => service.name)
                          .join(', '),
                      _date,
                      _time!,
                      widget.appointment?.status ?? 'Pending')),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _pickServices() async {
    final selected = await showDialog<List<ParlourService>>(
      context: context,
      builder: (context) => _ServiceMultiSelectDialog(
        services: widget.services,
        selectedServices: _selectedServices,
      ),
    );
    if (selected == null) return;
    setState(() {
      _selectedServices
        ..clear()
        ..addAll(selected);
    });
  }
}

class _ServiceMultiSelectDialog extends StatefulWidget {
  const _ServiceMultiSelectDialog({
    required this.services,
    required this.selectedServices,
  });

  final List<ParlourService> services;
  final List<ParlourService> selectedServices;

  @override
  State<_ServiceMultiSelectDialog> createState() =>
      _ServiceMultiSelectDialogState();
}

class _ServiceMultiSelectDialogState extends State<_ServiceMultiSelectDialog> {
  late final Set<String> _selectedNames;

  @override
  void initState() {
    super.initState();
    _selectedNames =
        widget.selectedServices.map((service) => service.name).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Services'),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: widget.services.isEmpty
            ? const Center(child: Text('No services available'))
            : ListView.builder(
                itemCount: widget.services.length,
                itemBuilder: (context, index) {
                  final service = widget.services[index];
                  final selected = _selectedNames.contains(service.name);
                  return CheckboxListTile(
                    value: selected,
                    title: Text(
                      service.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${service.durationMinutes} min'),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedNames.add(service.name);
                        } else {
                          _selectedNames.remove(service.name);
                        }
                      });
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final selected = widget.services
                .where((service) => _selectedNames.contains(service.name))
                .toList();
            Navigator.pop(context, selected);
          },
          child: Text('Apply (${_selectedNames.length})'),
        ),
      ],
    );
  }
}

class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({this.purchase, this.invoiceId});

  final PurchaseItem? purchase;
  final String? invoiceId;

  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  late final TextEditingController _dealerController;
  final List<_PurchaseLineControllers> _items = [];
  late DateTime _dateTime;
  late PaymentMode _paymentMode;

  bool get _isEditing => widget.purchase != null;

  @override
  void initState() {
    super.initState();
    final purchase = widget.purchase;
    _dealerController = TextEditingController(text: purchase?.dealer ?? '');
    _items.add(_PurchaseLineControllers(
      itemName: purchase?.itemName ?? '',
      unitPrice: purchase == null ? '' : purchase.unitPrice.toStringAsFixed(0),
      quantity: purchase == null ? '1' : _formatQuantity(purchase.quantity),
    ));
    _dateTime = purchase?.dateTime ?? DateTime.now();
    _paymentMode = purchase?.paymentMode ?? PaymentMode.cash;
  }

  @override
  void dispose() {
    _dealerController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItemRow() {
    setState(() => _items.add(_PurchaseLineControllers(quantity: '1')));
  }

  void _removeItemRow(int index) {
    if (_items.length == 1) return;
    final removed = _items.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _dateTime.hour,
        _dateTime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        _dateTime.year,
        _dateTime.month,
        _dateTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _save() {
    final purchases = <PurchaseItem>[];
    final dealer = _dealerController.text.trim();
    final nowId = DateTime.now().microsecondsSinceEpoch;
    final invoiceId =
        widget.purchase?.invoiceId ?? widget.invoiceId ?? 'PI-001';

    for (var i = 0; i < _items.length; i++) {
      final line = _items[i];
      final itemName = line.item.text.trim();
      final unitPrice = double.tryParse(line.price.text.trim()) ?? 0;
      final quantity = double.tryParse(line.quantity.text.trim()) ?? 0;
      if (itemName.isEmpty || unitPrice < 0 || quantity <= 0) continue;

      purchases.add(
        PurchaseItem(
          id: widget.purchase?.id ?? 'P-${nowId + i}',
          invoiceId: invoiceId,
          itemName: itemName,
          dealer: dealer,
          unitPrice: unitPrice,
          quantity: quantity,
          dateTime: _dateTime,
          paymentMode: _paymentMode,
        ),
      );
    }

    if (purchases.isEmpty) return;

    Navigator.pop(
      context,
      purchases,
    );
  }

  @override
  Widget build(BuildContext context) {
    final date =
        '${_dateTime.day.toString().padLeft(2, '0')}/${_dateTime.month.toString().padLeft(2, '0')}/${_dateTime.year}';
    final time = TimeOfDay.fromDateTime(_dateTime).format(context);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      title: Text(widget.purchase == null ? 'Add Purchase' : 'Edit Purchase'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _dealerController,
              decoration: const InputDecoration(
                labelText: 'Dealer',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Items',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (!_isEditing)
                  TextButton.icon(
                    onPressed: _addItemRow,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Item'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final line = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: line.item,
                              decoration: InputDecoration(
                                labelText: 'Item ${index + 1}',
                                prefixIcon:
                                    const Icon(Icons.inventory_2_outlined),
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          if (!_isEditing && _items.length > 1) ...[
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Remove item',
                              onPressed: () => _removeItemRow(index),
                              icon: const Icon(Icons.close),
                              color: Colors.red,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: line.price,
                              decoration: const InputDecoration(
                                labelText: 'Price',
                                prefixText: 'Rs. ',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: line.quantity,
                              decoration:
                                  const InputDecoration(labelText: 'Quantity'),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: FittedBox(child: Text(date)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: FittedBox(child: Text(time)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<PaymentMode>(
              value: _paymentMode,
              decoration: const InputDecoration(
                labelText: 'Payment Mode',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: PaymentMode.cash,
                  child: Text('Cash'),
                ),
                DropdownMenuItem(
                  value: PaymentMode.online,
                  child: Text('Online'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _paymentMode = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PurchaseLineControllers {
  _PurchaseLineControllers({
    String itemName = '',
    String unitPrice = '',
    String quantity = '1',
  })  : item = TextEditingController(text: itemName),
        price = TextEditingController(text: unitPrice),
        quantity = TextEditingController(text: quantity);

  final TextEditingController item;
  final TextEditingController price;
  final TextEditingController quantity;

  void dispose() {
    item.dispose();
    price.dispose();
    quantity.dispose();
  }
}

class _InvestmentDialog extends StatefulWidget {
  const _InvestmentDialog({this.transaction});

  final InvestmentTransaction? transaction;

  @override
  State<_InvestmentDialog> createState() => _InvestmentDialogState();
}

class _InvestmentDialogState extends State<_InvestmentDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late InvestmentType _type;
  late PaymentMode _paymentMode;
  late DateTime _dateTime;

  bool get _isEditing => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _titleController = TextEditingController(text: t?.title ?? '');
    _amountController = TextEditingController(
      text: t != null ? t.amount.toStringAsFixed(0) : '',
    );
    _noteController = TextEditingController(text: t?.note ?? '');
    _type = t?.type ?? InvestmentType.credit;
    _paymentMode = t?.paymentMode ?? PaymentMode.cash;
    _dateTime = t?.dateTime ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _dateTime.hour,
        _dateTime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        _dateTime.year,
        _dateTime.month,
        _dateTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _save() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a valid amount greater than 0.')),
      );
      return;
    }

    var title = _titleController.text.trim();
    if (title.isEmpty) {
      title = _type == InvestmentType.credit ? 'Investment' : 'Debit Expense';
    }

    final nowId = DateTime.now().microsecondsSinceEpoch;
    final item = InvestmentTransaction(
      id: widget.transaction?.id ?? 'INV-$nowId',
      title: title,
      amount: amount,
      type: _type,
      paymentMode: _paymentMode,
      dateTime: _dateTime,
      note: _noteController.text.trim(),
    );

    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final date =
        '${_dateTime.day.toString().padLeft(2, '0')}/${_dateTime.month.toString().padLeft(2, '0')}/${_dateTime.year}';
    final time = TimeOfDay.fromDateTime(_dateTime).format(context);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      title: Text(_isEditing ? 'Edit Transaction' : 'New Investment Entry'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<InvestmentType>(
              segments: const [
                ButtonSegment(
                  value: InvestmentType.credit,
                  icon:
                      Icon(Icons.south_west_rounded, color: Color(0xff059669)),
                  label: Text('Invest (Credit)'),
                ),
                ButtonSegment(
                  value: InvestmentType.debit,
                  icon:
                      Icon(Icons.north_east_rounded, color: Color(0xffdc2626)),
                  label: Text('Debit'),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: 'Rs. ',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: !_isEditing,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: _type == InvestmentType.credit
                    ? 'Title / Source (e.g. Self Invest, Capital)'
                    : 'Title / Purpose (e.g. Equipment, Personal Draw)',
                prefixIcon: const Icon(Icons.edit_note_rounded),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: (_type == InvestmentType.credit
                        ? [
                            'Self Invest',
                            'Parlour Capital',
                            'Partner Fund',
                            'Deposit'
                          ]
                        : [
                            'Equipment',
                            'Renovation',
                            'Personal Draw',
                            'Withdrawal'
                          ])
                    .map((suggestion) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(suggestion,
                          style: const TextStyle(fontSize: 11)),
                      padding: EdgeInsets.zero,
                      onPressed: () => _titleController.text = suggestion,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note / Remarks (Optional)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(date, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(time, style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<PaymentMode>(
              segments: const [
                ButtonSegment(
                  value: PaymentMode.cash,
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Cash'),
                ),
                ButtonSegment(
                  value: PaymentMode.online,
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  label: Text('Online'),
                ),
              ],
              selected: {_paymentMode},
              onSelectionChanged: (selection) =>
                  setState(() => _paymentMode = selection.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEditing ? 'Update' : 'Save'),
        ),
      ],
    );
  }
}

class _BillDialog extends StatefulWidget {
  const _BillDialog({
    required this.customers,
    required this.services,
    this.bill,
    this.initialCustomer,
    this.invoiceId,
  });

  final List<Customer> customers;
  final List<ParlourService> services;
  final Bill? bill;
  final Customer? initialCustomer;
  final String? invoiceId;

  @override
  State<_BillDialog> createState() => _BillDialogState();
}

class _BillDialogState extends State<_BillDialog> {
  Customer? _customer;
  late final TextEditingController _customerController;
  final List<ParlourService> _selectedServices = [];
  // Custom prices: service name -> overridden price (defaults to service.price)
  final Map<String, double> _customPrices = {};
  final Map<String, TextEditingController> _priceControllers = {};
  List<Customer> _filteredCustomers = [];
  bool _showCustomerSuggestions = false;
  PaymentMode? _paymentMode;
  DateTime _dateTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    final bill = widget.bill;
    // When editing an existing bill, pre-select its customer.
    // When creating a new bill, use initialCustomer if provided, else empty.
    _customer = bill == null
        ? widget.initialCustomer
        : widget.customers
            .where((c) => c.name == bill.customerName)
            .firstOrNull;
    _customerController = TextEditingController(text: _customer?.name ?? '');
    _dateTime = bill?.date ?? DateTime.now();
    // No default payment mode — user must select
    _paymentMode = (bill != null) ? bill.paymentMode : null;
    if (bill != null) {
      _selectedServices.addAll(
        widget.services
            .where((service) => bill.services.contains(service.name)),
      );
      // Restore custom prices from saved bill servicePrices,
      // fall back to even distribution of total if not stored yet
      for (final service in _selectedServices) {
        final savedPrice = bill.servicePrices[service.name];
        if (savedPrice != null) {
          _customPrices[service.name] = savedPrice;
        } else if (_selectedServices.isNotEmpty) {
          // Old bill: distribute total evenly across services
          _customPrices[service.name] = bill.total / _selectedServices.length;
        }
      }
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    for (final controller in _priceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onCustomerSearchChanged(String value) {
    final query = value.trim().toLowerCase();
    final phoneQuery = query.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _customer = null;
      if (query.isEmpty) {
        _filteredCustomers = [];
        _showCustomerSuggestions = false;
        return;
      }

      _filteredCustomers = widget.customers
          .where((customer) {
            final phone = customer.phone.replaceAll(RegExp(r'\D'), '');
            return customer.name.toLowerCase().contains(query) ||
                (phoneQuery.isNotEmpty && phone.contains(phoneQuery));
          })
          .take(6)
          .toList();
      _showCustomerSuggestions = _filteredCustomers.isNotEmpty;
    });
  }

  void _selectCustomer(Customer customer) {
    setState(() {
      _customer = customer;
      _customerController.text = customer.name;
      _filteredCustomers = [];
      _showCustomerSuggestions = false;
    });
  }

  TextEditingController _priceControllerFor(ParlourService service) {
    return _priceControllers.putIfAbsent(service.name, () {
      final price = _customPrices[service.name] ?? service.price;
      final controller = TextEditingController(text: price.toStringAsFixed(0));
      controller.addListener(() {
        final livePrice = double.tryParse(controller.text) ?? 0;
        _customPrices[service.name] = livePrice;
        if (mounted) setState(() {});
      });
      return controller;
    });
  }

  double _priceFor(ParlourService service) {
    final controller = _priceControllers[service.name];
    if (controller != null) {
      return double.tryParse(controller.text) ?? 0;
    }
    return _customPrices[service.name] ?? service.price;
  }

  Future<void> _pickBillDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _dateTime.hour,
        _dateTime.minute,
      );
    });
  }

  Future<void> _pickBillTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        _dateTime.year,
        _dateTime.month,
        _dateTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _addCustomerFromBill() async {
    final result = await showDialog<Customer>(
      context: context,
      builder: (_) => const _CustomerDialog(),
    );
    if (result == null) return;

    setState(() {
      widget.customers.add(result);
      _customer = result;
      _customerController.text = result.name;
      _filteredCustomers = [];
      _showCustomerSuggestions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total =
        _selectedServices.fold<double>(0, (sum, s) => sum + _priceFor(s));
    final billDate =
        '${_dateTime.day.toString().padLeft(2, '0')}/${_dateTime.month.toString().padLeft(2, '0')}/${_dateTime.year}';
    final billTime = TimeOfDay.fromDateTime(_dateTime).format(context);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.bill == null ? 'Create Bill' : 'Edit Bill'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: _customerController,
                        decoration: InputDecoration(
                          labelText: 'Customer',
                          hintText: 'Select customer',
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: const Icon(Icons.person_search_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xffCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xffCBD5E1)),
                          ),
                        ),
                        onChanged: _onCustomerSearchChanged,
                        onTap: () {
                          final text = _customerController.text;
                          if (text.trim().isNotEmpty) {
                            _onCustomerSearchChanged(text);
                          }
                        },
                      ),
                      if (_showCustomerSuggestions)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 224),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filteredCustomers.length,
                            itemBuilder: (context, index) {
                              final customer = _filteredCustomers[index];
                              final initial = customer.name.isEmpty
                                  ? '?'
                                  : customer.name[0].toUpperCase();
                              return ListTile(
                                dense: true,
                                minVerticalPadding: 4,
                                visualDensity: VisualDensity.compact,
                                leading: CircleAvatar(
                                  radius: 14,
                                  child: Text(
                                    initial,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                title: Text(
                                  customer.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  customer.phone,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onTap: () => _selectCustomer(customer),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Add customer',
                  onPressed: _addCustomerFromBill,
                  icon: const Icon(Icons.person_add_alt_1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xff0F172A),
                      side: const BorderSide(color: Color(0xffCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _pickBillDate,
                    icon: const Icon(Icons.calendar_today, size: 17, color: Color(0xff0369A1)),
                    label: FittedBox(child: Text(billDate, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xff0F172A),
                      side: const BorderSide(color: Color(0xffCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _pickBillTime,
                    icon: const Icon(Icons.schedule, size: 17, color: Color(0xff0369A1)),
                    label: FittedBox(child: Text(billTime, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Select Services',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            // Each service as a row: chip + price field when selected
            ...widget.services.map((service) {
              final isSelected = _selectedServices.contains(service);
              return _ServiceSelectRow(
                key: ValueKey(service.name),
                service: service,
                isSelected: isSelected,
                priceController: _priceControllerFor(service),
                onToggle: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedServices.add(service);
                      final controller = _priceControllerFor(service);
                      if (controller.text.isEmpty) {
                        controller.text = service.price.toStringAsFixed(0);
                      }
                      _customPrices[service.name] =
                          double.tryParse(controller.text) ?? service.price;
                    } else {
                      _selectedServices.remove(service);
                    }
                  });
                },
              );
            }),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Amount:',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(money(total),
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: Theme.of(context).colorScheme.primary)),
                ],
              ),
              const SizedBox(height: 10),
              // Payment mode toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PaymentModeOption(
                          label: 'Cash',
                          icon: Icons.payments_outlined,
                          isSelected: _paymentMode == PaymentMode.cash,
                          onTap: () {
                            if (_paymentMode != PaymentMode.cash) {
                              setState(() => _paymentMode = PaymentMode.cash);
                            }
                          },
                        ),
                        _PaymentModeOption(
                          label: 'Online',
                          icon: Icons.account_balance_wallet_outlined,
                          isSelected: _paymentMode == PaymentMode.online,
                          onTap: () {
                            if (_paymentMode != PaymentMode.online) {
                              setState(() => _paymentMode = PaymentMode.online);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Cancel + Save buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(54, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _customer == null || _selectedServices.isEmpty || _paymentMode == null
                        ? null
                        : () {
                            final customTotal = _selectedServices.fold<double>(
                                0, (sum, s) => sum + _priceFor(s));
                            final prices = {
                              for (final s in _selectedServices)
                                s.name: _priceFor(s)
                            };
                            Navigator.pop(
                              context,
                              Bill(
                                widget.bill?.id ?? widget.invoiceId ?? '001',
                                _customer!.name,
                                _selectedServices.map((s) => s.name).toList(),
                                customTotal,
                                _dateTime,
                                _paymentMode!,
                                prices,
                              ),
                            );
                          },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(68, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Segmented payment mode option pill
class _PaymentModeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentModeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xff1E293B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : const Color(0xff1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row: service chip on left, price input on right when selected
class _ServiceSelectRow extends StatefulWidget {
  final ParlourService service;
  final bool isSelected;
  final TextEditingController priceController;
  final ValueChanged<bool> onToggle;

  const _ServiceSelectRow({
    super.key,
    required this.service,
    required this.isSelected,
    required this.priceController,
    required this.onToggle,
  });

  @override
  State<_ServiceSelectRow> createState() => _ServiceSelectRowState();
}

class _ServiceSelectRowState extends State<_ServiceSelectRow> {
  void _commit() {
    final value = double.tryParse(widget.priceController.text);
    if (value == null || value < 0) {
      widget.priceController.text = widget.service.price.toStringAsFixed(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final livePrice =
        double.tryParse(widget.priceController.text) ?? widget.service.price;
    final isCustom = widget.isSelected && livePrice != widget.service.price;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Tap the left part to toggle selection
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onToggle(!widget.isSelected),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? primary.withValues(alpha: 0.12)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.isSelected ? primary : const Color(0xffCBD5E1),
                    width: widget.isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: widget.isSelected ? primary : const Color(0xff475569),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.service.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: widget.isSelected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: widget.isSelected
                              ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : primary)
                              : const Color(0xff0F172A),
                        ),
                      ),
                    ),
                    if (!widget.isSelected)
                      Text(
                        'Rs. ${widget.service.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff1E293B),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Price input — only visible when selected
          if (widget.isSelected) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: TextField(
                controller: widget.priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isCustom ? primary : Colors.green.shade700,
                ),
                decoration: InputDecoration(
                  prefixText: 'Rs. ',
                  prefixStyle: TextStyle(
                    color: isCustom ? primary : Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isCustom ? primary : Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isCustom ? primary : Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: primary, width: 2),
                  ),
                ),
                onTap: () {
                  if (widget.priceController.text == '0') {
                    widget.priceController.clear();
                  }
                },
                onSubmitted: (_) => _commit(),
                onEditingComplete: _commit,
                onTapOutside: (_) => _commit(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class Customer {
  const Customer(this.id, this.name, this.phone, this.note,
      {this.referredBy = ''});

  final String id;
  final String name;
  final String phone;
  final String note;
  final String referredBy;

  Customer copyWith({String? referredBy}) {
    return Customer(id, name, phone, note,
        referredBy: referredBy ?? this.referredBy);
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      json['id'] as String? ?? '',
      json['name'] as String? ?? '',
      json['phone'] as String? ?? '',
      json['note'] as String? ?? '',
      referredBy: json['referredBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'note': note,
      'referredBy': referredBy,
    };
  }
}

class _CustomerImportColumns {
  const _CustomerImportColumns({
    required this.name,
    required this.phone,
    required this.note,
    required this.referredBy,
  });

  final int name;
  final int phone;
  final int note;
  final int referredBy;

  _CustomerImportColumns copyWith({
    int? name,
    int? phone,
    int? note,
    int? referredBy,
  }) {
    return _CustomerImportColumns(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      note: note ?? this.note,
      referredBy: referredBy ?? this.referredBy,
    );
  }
}

class ParlourService {
  const ParlourService(
      this.name, this.category, this.price, this.durationMinutes);

  final String name;
  final String category;
  final double price;
  final int durationMinutes;

  factory ParlourService.fromJson(Map<String, dynamic> json) {
    return ParlourService(
      json['name'] as String? ?? '',
      json['category'] as String? ?? '',
      (json['price'] as num?)?.toDouble() ?? 0,
      (json['durationMinutes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'price': price,
      'durationMinutes': durationMinutes,
    };
  }
}

class Appointment {
  const Appointment(
    this.customerName,
    this.serviceName,
    this.date,
    this.time,
    this.status, [
    this.confirmationPollId,
  ]);

  final String customerName;
  final String serviceName;
  final DateTime date;
  final TimeOfDay time;
  final String status;
  final String? confirmationPollId;

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      json['customerName'] as String? ?? '',
      json['serviceName'] as String? ?? '',
      DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      TimeOfDay(
        hour: (json['hour'] as num?)?.toInt() ?? 0,
        minute: (json['minute'] as num?)?.toInt() ?? 0,
      ),
      json['status'] as String? ?? 'Pending',
      json['confirmationPollId'] as String?,
    );
  }

  Appointment copyWith({
    String? customerName,
    String? serviceName,
    DateTime? date,
    TimeOfDay? time,
    String? status,
    String? confirmationPollId,
  }) {
    return Appointment(
      customerName ?? this.customerName,
      serviceName ?? this.serviceName,
      date ?? this.date,
      time ?? this.time,
      status ?? this.status,
      confirmationPollId ?? this.confirmationPollId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customerName': customerName,
      'serviceName': serviceName,
      'date': date.toIso8601String(),
      'hour': time.hour,
      'minute': time.minute,
      'status': status,
      'confirmationPollId': confirmationPollId,
    };
  }
}

class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.invoiceId,
    required this.itemName,
    required this.dealer,
    required this.unitPrice,
    required this.quantity,
    required this.dateTime,
    required this.paymentMode,
  });

  final String id;
  final String invoiceId;
  final String itemName;
  final String dealer;
  final double unitPrice;
  final double quantity;
  final DateTime dateTime;
  final PaymentMode paymentMode;

  double get total => unitPrice * quantity;

  factory PurchaseItem.fromJson(Map<String, dynamic> json) {
    return PurchaseItem(
      id: json['id'] as String? ?? '',
      invoiceId:
          json['invoiceId'] as String? ?? (json['id'] as String? ?? 'PI-001'),
      itemName: json['itemName'] as String? ?? '',
      dealer: json['dealer'] as String? ?? '',
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      dateTime: DateTime.tryParse(json['dateTime'] as String? ?? '') ??
          DateTime.now(),
      paymentMode: PaymentMode.values.firstWhere(
        (mode) => mode.name == json['paymentMode'],
        orElse: () => PaymentMode.cash,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'invoiceId': invoiceId,
      'itemName': itemName,
      'dealer': dealer,
      'unitPrice': unitPrice,
      'quantity': quantity,
      'dateTime': dateTime.toIso8601String(),
      'paymentMode': paymentMode.name,
    };
  }
}

enum PaymentMode { cash, online }

extension PaymentModeLabel on PaymentMode {
  String get label {
    switch (this) {
      case PaymentMode.cash:
        return 'Cash';
      case PaymentMode.online:
        return 'Online';
    }
  }
}

enum InvestmentType { credit, debit }

extension InvestmentTypeLabel on InvestmentType {
  String get label {
    switch (this) {
      case InvestmentType.credit:
        return 'Invest (Credit)';
      case InvestmentType.debit:
        return 'Debit';
    }
  }

  String get shortLabel {
    switch (this) {
      case InvestmentType.credit:
        return 'Credit';
      case InvestmentType.debit:
        return 'Debit';
    }
  }
}

class InvestmentTransaction {
  const InvestmentTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.paymentMode,
    required this.dateTime,
    this.note = '',
  });

  final String id;
  final String title;
  final double amount;
  final InvestmentType type;
  final PaymentMode paymentMode;
  final DateTime dateTime;
  final String note;

  factory InvestmentTransaction.fromJson(Map<String, dynamic> json) {
    return InvestmentTransaction(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      type: InvestmentType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => InvestmentType.credit,
      ),
      paymentMode: PaymentMode.values.firstWhere(
        (mode) => mode.name == json['paymentMode'],
        orElse: () => PaymentMode.cash,
      ),
      dateTime: DateTime.tryParse(json['dateTime'] as String? ?? '') ??
          DateTime.now(),
      note: json['note'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'type': type.name,
      'paymentMode': paymentMode.name,
      'dateTime': dateTime.toIso8601String(),
      'note': note,
    };
  }

  InvestmentTransaction copyWith({
    String? id,
    String? title,
    double? amount,
    InvestmentType? type,
    PaymentMode? paymentMode,
    DateTime? dateTime,
    String? note,
  }) {
    return InvestmentTransaction(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      paymentMode: paymentMode ?? this.paymentMode,
      dateTime: dateTime ?? this.dateTime,
      note: note ?? this.note,
    );
  }
}


class Bill {
  const Bill(this.id, this.customerName, this.services, this.total, this.date,
      [this.paymentMode = PaymentMode.cash, this.servicePrices = const {}]);
  final String id;
  final String customerName;
  final List<String> services;
  final double total;
  final DateTime date;
  final PaymentMode paymentMode;
  final Map<String, double> servicePrices; // service name → price

  factory Bill.fromJson(Map<String, dynamic> json) {
    final pricesRaw = json['servicePrices'];
    final Map<String, double> prices = {};
    if (pricesRaw is Map) {
      pricesRaw.forEach((k, v) {
        if (v is num) prices[k.toString()] = v.toDouble();
      });
    }
    return Bill(
      json['id'] as String? ?? '',
      json['customerName'] as String? ?? '',
      (json['services'] as List? ?? []).whereType<String>().toList(),
      (json['total'] as num?)?.toDouble() ?? 0,
      DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      PaymentMode.values.firstWhere(
        (mode) => mode.name == json['paymentMode'],
        orElse: () => PaymentMode.cash,
      ),
      prices,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerName': customerName,
      'services': services,
      'total': total,
      'date': date.toIso8601String(),
      'paymentMode': paymentMode.name,
      'servicePrices': servicePrices,
    };
  }
}

class _Metric {
  const _Metric(
    this.label,
    this.value,
    this.icon,
    this.color, {
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
}

String money(double amount) => 'Rs. ${amount.toStringAsFixed(0)}';

bool _isDateInRange(DateTime date, DateTime start, DateTime end) {
  final normalizedDate = DateTime(date.year, date.month, date.day);
  final normalizedStart = DateTime(start.year, start.month, start.day);
  final normalizedEnd = DateTime(end.year, end.month, end.day);
  return !normalizedDate.isBefore(normalizedStart) &&
      !normalizedDate.isAfter(normalizedEnd);
}

String _shortDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

class _CustomerDetailsPage extends StatefulWidget {
  const _CustomerDetailsPage({
    required this.customer,
    required this.bills,
    required this.appointments,
    required this.onUpdated,
    this.onAddBill,
  });

  final Customer customer;
  final List<Bill> bills;
  final List<Appointment> appointments;
  final Future<void> Function(Customer customer) onUpdated;
  final VoidCallback? onAddBill;

  @override
  State<_CustomerDetailsPage> createState() => _CustomerDetailsPageState();
}

class _CustomerDetailsPageState extends State<_CustomerDetailsPage> {
  late Customer _customer;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
  }

  Future<void> _editCustomer() async {
    final result = await showDialog<Customer>(
      context: context,
      builder: (context) => _CustomerDialog(customer: _customer),
    );
    if (result == null) return;

    await widget.onUpdated(result);
    setState(() => _customer = result);
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;
    final primary = Theme.of(context).colorScheme.primary;

    // Bills for this customer
    final customerBills = widget.bills
        .where((b) => b.customerName == customer.name)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final totalSpent = customerBills.fold<double>(0, (sum, b) => sum + b.total);

    // Latest appointment for this customer
    final customerAppointments = widget.appointments
        .where((a) => a.customerName == customer.name)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final latestAppointment =
        customerAppointments.isNotEmpty ? customerAppointments.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Details'),
        actions: [
          IconButton(
            tooltip: 'Edit client',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editCustomer,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Avatar + name ──────────────────────────────────────────────
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: primary.withOpacity(0.1),
              child: Text(
                  customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: primary)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
              child: Text(customer.name,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold))),
          const SizedBox(height: 24),

          // ── Stats row: orders + total spent ───────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.receipt_long_outlined,
                  label: 'Total Orders',
                  value: customerBills.length.toString(),
                  color: const Color(0xff7c3aed),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.currency_rupee,
                  label: 'Total Spent',
                  value: 'Rs. ${totalSpent.toStringAsFixed(0)}',
                  color: const Color(0xff0f766e),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Contact info ───────────────────────────────────────────────
          _DetailRow(
              icon: Icons.phone, label: 'Phone Number', value: customer.phone),
          const SizedBox(height: 12),
          _DetailRow(
              icon: Icons.note,
              label: 'Notes',
              value:
                  customer.note.isEmpty ? 'No notes provided' : customer.note),
          if (customer.referredBy.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailRow(
                icon: Icons.handshake,
                label: 'Referred By',
                value: customer.referredBy),
          ],

          // ── Latest appointment ─────────────────────────────────────────
          if (latestAppointment != null) ...[
            const SizedBox(height: 20),
            Text('Latest Appointment',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primary.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                      color: _softShadowColor(context),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: primary.withOpacity(0.08),
                        shape: BoxShape.circle),
                    child: Icon(Icons.calendar_today, color: primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(latestAppointment.serviceName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(
                          '${latestAppointment.date.day.toString().padLeft(2, '0')}/${latestAppointment.date.month.toString().padLeft(2, '0')}/${latestAppointment.date.year}  •  ${latestAppointment.time.format(context)}',
                          style: TextStyle(
                              color: _mutedTextColor(context), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _apptStatusColor(latestAppointment.status)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      latestAppointment.status,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _apptStatusColor(latestAppointment.status)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Bills history ──────────────────────────────────────────────
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Bills History',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface)),
              const Spacer(),
              Text(
                  '${customerBills.length} bill${customerBills.length == 1 ? '' : 's'}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          if (customerBills.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('No bills yet',
                    style: TextStyle(color: Colors.grey.shade400)),
              ),
            )
          else
            ...customerBills.map((bill) => _BillTileV2(bill: bill)),

          const SizedBox(height: 24),

          // ── Action buttons ─────────────────────────────────────────────
          Row(
            children: [
              if (widget.onAddBill != null) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => widget.onAddBill?.call(),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Create Bill'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                if (customer.phone.isNotEmpty) const SizedBox(width: 12),
              ],
              if (customer.phone.isNotEmpty)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final url = Uri.parse('tel:${customer.phone}');
                      if (await canLaunchUrl(url)) await launchUrl(url);
                    },
                    icon: const Icon(Icons.call),
                    label: const Text('Call Customer'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _apptStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: _isDarkMode(context)
                  ? Colors.black.withOpacity(0.25)
                  : color.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: _mutedTextColor(context), fontSize: 12)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _cardColor(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: _softShadowColor(context),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ]),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                shape: BoxShape.circle),
            child: Icon(icon,
                color: Theme.of(context).colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: _mutedTextColor(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: valueColor ??
                            Theme.of(context).colorScheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
