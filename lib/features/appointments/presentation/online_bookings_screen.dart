import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Data model representing an Online Booking Request from Web Form
class OnlineBooking {
  const OnlineBooking({
    required this.id,
    required this.bookingRef,
    required this.customerName,
    required this.customerPhone,
    required this.serviceNames,
    required this.totalAmount,
    required this.bookingDate,
    required this.timeSlot,
    required this.status, // 'Pending', 'Confirmed', 'Cancelled'
    required this.createdAt,
    this.notes = '',
  });

  final String id;
  final String bookingRef;
  final String customerName;
  final String customerPhone;
  final String serviceNames;
  final double totalAmount;
  final DateTime bookingDate;
  final String timeSlot;
  final String status;
  final DateTime createdAt;
  final String notes;

  factory OnlineBooking.fromJson(Map<String, dynamic> json, [String? docId]) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(json['bookingDate'] as String? ?? '');
    } catch (_) {
      parsedDate = DateTime.now();
    }

    DateTime parsedCreated;
    try {
      parsedCreated = DateTime.parse(json['createdAt'] as String? ?? '');
    } catch (_) {
      parsedCreated = DateTime.now();
    }

    return OnlineBooking(
      id: docId ?? json['id'] as String? ?? 'ob_${DateTime.now().millisecondsSinceEpoch}',
      bookingRef: json['bookingRef'] as String? ?? 'NP-${(100000 + (docId.hashCode % 900000)).abs()}',
      customerName: json['customerName'] as String? ?? 'Unknown Customer',
      customerPhone: json['customerPhone'] as String? ?? '',
      serviceNames: json['serviceNames'] as String? ?? 'General Parlour Service',
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      bookingDate: parsedDate,
      timeSlot: json['timeSlot'] as String? ?? '10:00 AM',
      status: json['status'] as String? ?? 'Pending',
      createdAt: parsedCreated,
      notes: json['notes'] as String? ?? '',
    );
  }

  factory OnlineBooking.fromFirestoreDoc(Map<String, dynamic> doc) {
    final namePath = doc['name'] as String? ?? '';
    final docId = namePath.split('/').last;
    final fields = doc['fields'] as Map<String, dynamic>? ?? {};

    String getString(String key, [String def = '']) {
      final f = fields[key];
      if (f is Map && f.containsKey('stringValue')) {
        return f['stringValue'] as String? ?? def;
      }
      return def;
    }

    double getDouble(String key, [double def = 0.0]) {
      final f = fields[key];
      if (f is Map) {
        if (f.containsKey('doubleValue')) {
          return (f['doubleValue'] as num?)?.toDouble() ?? def;
        }
        if (f.containsKey('integerValue')) {
          return double.tryParse(f['integerValue'].toString()) ?? def;
        }
      }
      return def;
    }

    DateTime parseDate(String val) {
      try {
        return DateTime.parse(val);
      } catch (_) {
        return DateTime.now();
      }
    }

    return OnlineBooking(
      id: docId,
      bookingRef: getString('bookingRef', 'NP-${(100000 + (docId.hashCode % 900000)).abs()}'),
      customerName: getString('customerName', 'Unknown Customer'),
      customerPhone: getString('customerPhone', ''),
      serviceNames: getString('serviceNames', 'General Parlour Service'),
      totalAmount: getDouble('totalAmount', 0.0),
      bookingDate: parseDate(getString('bookingDate')),
      timeSlot: getString('timeSlot', '10:00 AM'),
      status: getString('status', 'Pending'),
      createdAt: parseDate(getString('createdAt', doc['createTime'] as String? ?? '')),
      notes: getString('notes', ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookingRef': bookingRef,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'serviceNames': serviceNames,
      'totalAmount': totalAmount,
      'bookingDate': DateFormat('yyyy-MM-dd').format(bookingDate),
      'timeSlot': timeSlot,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'notes': notes,
    };
  }

  OnlineBooking copyWith({
    String? status,
    String? notes,
  }) {
    return OnlineBooking(
      id: id,
      bookingRef: bookingRef,
      customerName: customerName,
      customerPhone: customerPhone,
      serviceNames: serviceNames,
      totalAmount: totalAmount,
      bookingDate: bookingDate,
      timeSlot: timeSlot,
      status: status ?? this.status,
      createdAt: createdAt,
      notes: notes ?? this.notes,
    );
  }
}

/// Firebase Firestore & Live Backend API Service for Online Bookings
class FirestoreBookingService {
  static const String defaultProjectId = 'parlour-management-app';
  static const String defaultBookingUrl =
      'https://nupur-beauty-parlour.onrender.com/';
  static const String cloudStorageUrl =
      'https://api.restful-api.dev/objects/ff808181a09d98f701a124c3537f33ed';
  static const String defaultBackendApiUrl =
      'https://nupur-beauty-parlour.onrender.com/api';
  static const List<String> backendEndpoints = [
    'https://nupur-beauty-parlour.onrender.com/api',
    'https://nupur-beauty-parlour-api.onrender.com/api',
    'http://192.168.1.11:10000/api',
  ];
  static const String prefsKeyProjectId = 'firebase_firestore_project_id';
  static const String prefsKeyBookingUrl = 'online_booking_web_url';

  static Future<String> getProjectId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefsKeyProjectId) ?? defaultProjectId;
  }

  static Future<void> saveProjectId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKeyProjectId, id.trim());
  }

  static Future<String> getBookingUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefsKeyBookingUrl) ?? defaultBookingUrl;
  }

  static Future<void> saveBookingUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKeyBookingUrl, url.trim());
  }

  /// Fetch bookings from Global Cloud Store and live Backend API
  static Future<List<OnlineBooking>> fetchFromBackendApi() async {
    // 1. Fetch from Global Cloud Store (instant 24/7 internet sync without any server)
    try {
      final res = await http
          .get(Uri.parse(cloudStorageUrl))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['data'] is Map) {
          final list = decoded['data']['bookings'] as List<dynamic>? ?? [];
          if (list.isNotEmpty) {
            return list
                .map((e) => OnlineBooking.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
      }
    } catch (e) {
      debugPrint('Cloud DB fetch error: $e');
    }

    // 2. Fetch from backendEndpoints
    for (final base in backendEndpoints) {
      try {
        final url = Uri.parse('$base/bookings');
        final response =
            await http.get(url).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is List) {
            return decoded
                .map((e) => OnlineBooking.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
      } catch (_) {}
    }
    return [];
  }

  /// Update booking status on Global Cloud Store & Backend API ('Confirmed' or 'Cancelled')
  static Future<bool> updateStatusOnBackendApi({
    required String bookingId,
    required String newStatus,
  }) async {
    bool ok = false;

    // 1. Update in Global Cloud Store
    try {
      final res = await http
          .get(Uri.parse(cloudStorageUrl))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>? ?? {};
        final list = data['bookings'] as List<dynamic>? ?? [];
        for (var item in list) {
          if (item is Map &&
              (item['id'] == bookingId || item['bookingRef'] == bookingId)) {
            item['status'] = newStatus;
          }
        }
        final putRes = await http
            .put(
              Uri.parse(cloudStorageUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(
                  {'name': 'nupur_bookings', 'data': {'bookings': list}}),
            )
            .timeout(const Duration(seconds: 5));
        if (putRes.statusCode == 200) {
          ok = true;
        }
      }
    } catch (e) {
      debugPrint('Cloud status update error: $e');
    }

    // 2. Update on backendEndpoints
    for (final base in backendEndpoints) {
      try {
        final url = Uri.parse('$base/bookings/$bookingId/status');
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'status': newStatus}),
            )
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          ok = true;
        }
      } catch (_) {}
    }
    return ok;
  }

  /// Sync app manual appointments to Backend API so slots are locked on website
  static Future<bool> syncAppAppointmentsToBackendApi(
      List<Map<String, dynamic>> appointments) async {
    bool ok = false;
    for (final base in backendEndpoints) {
      try {
        final url = Uri.parse('$base/sync-app-appointments');
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'appointments': appointments}),
            )
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          ok = true;
        }
      } catch (_) {}
    }
    return ok;
  }

  /// Fetch bookings from Firestore REST API
  static Future<List<OnlineBooking>> fetchFromFirestore(String projectId) async {
    final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/online_bookings',
    );
    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['documents'] as List<dynamic>? ?? [];
      return docs
          .map((d) => OnlineBooking.fromFirestoreDoc(d as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Firestore HTTP ${response.statusCode}: ${response.body}');
    }
  }

  /// Update booking status in Firestore ('Confirmed' or 'Cancelled')
  static Future<bool> updateStatusInFirestore({
    required String projectId,
    required String docId,
    required String newStatus,
  }) async {
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/online_bookings/$docId?updateMask.fieldPaths=status',
      );
      final response = await http
          .patch(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'fields': {
                'status': {'stringValue': newStatus},
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating Firestore status: $e');
      return false;
    }
  }

  /// Create a new booking / lock slot in Firestore
  static Future<bool> createBookingInFirestore({
    required String projectId,
    required OnlineBooking booking,
  }) async {
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/online_bookings?documentId=${booking.id}',
      );
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'fields': {
                'bookingRef': {'stringValue': booking.bookingRef},
                'customerName': {'stringValue': booking.customerName},
                'customerPhone': {'stringValue': booking.customerPhone},
                'serviceNames': {'stringValue': booking.serviceNames},
                'totalAmount': {'doubleValue': booking.totalAmount},
                'bookingDate': {
                  'stringValue':
                      DateFormat('yyyy-MM-dd').format(booking.bookingDate)
                },
                'timeSlot': {'stringValue': booking.timeSlot},
                'status': {'stringValue': booking.status},
                'notes': {'stringValue': booking.notes},
                'createdAt': {'stringValue': booking.createdAt.toIso8601String()},
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error creating Firestore booking: $e');
      return false;
    }
  }
}

class OnlineBookingsScreen extends StatefulWidget {
  const OnlineBookingsScreen({
    super.key,
    required this.parlourName,
    required this.shopPhone,
    required this.shopAddress,
    this.existingAppointments,
    required this.onAddConfirmedAppointment,
  });

  final String parlourName;
  final String shopPhone;
  final String shopAddress;
  final List<Map<String, dynamic>>? existingAppointments;
  final Future<void> Function({
    required String customerName,
    required String customerPhone,
    required String serviceName,
    required DateTime date,
    required TimeOfDay time,
    required double amount,
  }) onAddConfirmedAppointment;

  @override
  State<OnlineBookingsScreen> createState() => _OnlineBookingsScreenState();
}

class _OnlineBookingsScreenState extends State<OnlineBookingsScreen> {
  static const String _storageKey = 'nupur_online_bookings_list';
  List<OnlineBooking> _bookings = [];
  String _selectedFilter = 'Pending';
  bool _isLoading = false;
  String _firebaseProjectId = FirestoreBookingService.defaultProjectId;
  String _bookingWebUrl = FirestoreBookingService.defaultBookingUrl;
  bool _hasPromptedPending = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndBookings();
  }

  Future<void> _loadSettingsAndBookings() async {
    final projId = await FirestoreBookingService.getProjectId();
    final url = await FirestoreBookingService.getBookingUrl();
    if (mounted) {
      setState(() {
        _firebaseProjectId = projId;
        _bookingWebUrl = url;
      });
    }
    await _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);

    // 1. Load from local cache first
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_storageKey);
    List<OnlineBooking> localList = [];

    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(rawJson) as List<dynamic>;
        localList = list
            .map((item) => OnlineBooking.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Error decoding local bookings: $e');
      }
    }

    // 2. Fetch live from Render Backend API
    bool syncedWithBackend = false;
    try {
      final apiList = await FirestoreBookingService.fetchFromBackendApi();
      if (apiList.isNotEmpty) {
        final Map<String, OnlineBooking> map = {
          for (var b in localList) b.id: b,
        };
        for (var b in apiList) {
          map[b.id] = b;
        }
        localList = map.values.toList();
        syncedWithBackend = true;
      }
    } catch (e) {
      debugPrint('Backend API fetch error: $e');
    }

    // 3. Fetch live from Firestore if configured
    bool syncedWithFirestore = false;
    try {
      if (_firebaseProjectId.isNotEmpty && _firebaseProjectId != FirestoreBookingService.defaultProjectId) {
        final firestoreList =
            await FirestoreBookingService.fetchFromFirestore(_firebaseProjectId);
        if (firestoreList.isNotEmpty) {
          final Map<String, OnlineBooking> map = {
            for (var b in localList) b.id: b,
          };
          for (var b in firestoreList) {
            map[b.id] = b;
          }
          localList = map.values.toList();
          syncedWithFirestore = true;
        }
      }
    } catch (e) {
      debugPrint('Firestore fetch failed (using local cache): $e');
    }

    // 4. Fallback mock data if completely empty
    if (localList.isEmpty) {
      localList = [
        OnlineBooking(
          id: 'ob_01',
          bookingRef: 'NP-582910',
          customerName: 'Pooja Patel',
          customerPhone: '9876543210',
          serviceNames: 'Festive Golden Glow Package (Facial + D-Tan + Wax), Hair Spa',
          totalAmount: 2149.0,
          bookingDate: DateTime.now().add(const Duration(days: 1)),
          timeSlot: '10:30 AM',
          status: 'Pending',
          createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
          notes: 'Festive party makeup inquiry as well.',
        ),
      ];
    }

    // Sort by created descending
    localList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _bookings = localList;
    await _saveBookings();

    if (mounted) {
      setState(() => _isLoading = false);

      if (syncedWithFirestore) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Synced with Firebase Firestore!'),
            backgroundColor: Color(0xff0369A1),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Check if there are pending bookings and automatically prompt confirmation
      _checkAndPromptPendingBooking();
    }
  }

  void _checkAndPromptPendingBooking() {
    if (_hasPromptedPending) return;
    final pending = _bookings.where((b) => b.status == 'Pending').toList();
    if (pending.isNotEmpty) {
      _hasPromptedPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showConfirmationRequestDialog(pending.first);
        }
      });
    }
  }

  Future<void> _saveBookings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_bookings.map((b) => b.toJson()).toList());
    await prefs.setString(_storageKey, raw);
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

  /// Primary Ask Confirmation Request Dialog
  Future<void> _showConfirmationRequestDialog(OnlineBooking booking) async {
    final dateFormatted = DateFormat('dd/MM/yyyy (EEEE)').format(booking.bookingDate);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.notifications_active_rounded,
                  color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'નવી બુકિંગ વિનંતી!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: Color(0xff0F172A),
                    ),
                  ),
                  Text(
                    'New Online Booking Request',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            const SizedBox(height: 6),
            _buildDetailRow(Icons.person_rounded, 'ગ્રાહક (Customer):', booking.customerName),
            _buildDetailRow(Icons.phone_rounded, 'મોબાઈલ (Mobile):', booking.customerPhone),
            _buildDetailRow(Icons.calendar_today_rounded, 'તારીખ (Date):', dateFormatted),
            _buildDetailRow(Icons.access_time_rounded, 'સમય સ્લોટ (Slot):', booking.timeSlot, isHighlight: true),
            _buildDetailRow(Icons.auto_awesome, 'સર્વિસ (Services):', booking.serviceNames),
            _buildDetailRow(Icons.currency_rupee_rounded, 'કુલ રકમ (Total):', '₹${booking.totalAmount.toStringAsFixed(0)}', isBold: true),
            if (booking.notes.isNotEmpty)
              _buildDetailRow(Icons.edit_note_rounded, 'નોંધ (Note):', booking.notes),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xffF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'કન્ફર્મ કરતાં જ સ્લોટ વેબસાઇટ પર ડિસેબલ થઈ જશે અને ગ્રાહકને WhatsApp મેસેજ જશે.',
                      style: TextStyle(fontSize: 11.5, color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _cancelBooking(booking);
            },
            child: const Text('❌ રદ કરો (Reject)'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff0369A1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _confirmBooking(booking);
            },
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('✅ કન્ફર્મ & WhatsApp'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String val,
      {bool isHighlight = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xff0369A1)),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              val,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold || isHighlight ? FontWeight.bold : FontWeight.w600,
                color: isHighlight
                    ? const Color(0xff0369A1)
                    : (isBold ? Colors.black87 : const Color(0xff1E293B)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Confirm Booking: Updates Firestore, adds to app schedule, launches WhatsApp
  Future<void> _confirmBooking(OnlineBooking booking) async {
    final timeOfDay = _parseTimeOfDay(booking.timeSlot);

    // 1. Add to local appointment schedule
    await widget.onAddConfirmedAppointment(
      customerName: booking.customerName,
      customerPhone: booking.customerPhone,
      serviceName: booking.serviceNames,
      date: booking.bookingDate,
      time: timeOfDay,
      amount: booking.totalAmount,
    );

    // 2. Update status in Render Backend API & Firestore
    await FirestoreBookingService.updateStatusOnBackendApi(
      bookingId: booking.id,
      newStatus: 'Confirmed',
    );
    if (_firebaseProjectId.isNotEmpty && _firebaseProjectId != FirestoreBookingService.defaultProjectId) {
      await FirestoreBookingService.updateStatusInFirestore(
        projectId: _firebaseProjectId,
        docId: booking.id,
        newStatus: 'Confirmed',
      );
    }

    // 3. Update local state
    setState(() {
      final index = _bookings.indexWhere((b) => b.id == booking.id);
      if (index != -1) {
        _bookings[index] = _bookings[index].copyWith(status: 'Confirmed');
      }
    });
    await _saveBookings();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Booking confirmed for ${booking.customerName}! WhatsApp is opening...'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 3),
      ),
    );

    // 4. Send Bilingual WhatsApp Confirmation
    await _sendBilingualWhatsAppConfirmation(booking);
  }

  /// Send Bilingual WhatsApp Confirmation Message to customer
  Future<void> _sendBilingualWhatsAppConfirmation(OnlineBooking booking) async {
    final phone = _cleanPhoneForWhatsApp(booking.customerPhone);
    final dateFormatted = DateFormat('dd/MM/yyyy').format(booking.bookingDate);
    final parlour = widget.parlourName.isNotEmpty ? widget.parlourName : 'Nupur Beauty Parlour';
    final address = widget.shopAddress.isNotEmpty ? widget.shopAddress : 'Nupur Beauty Parlour (Only for Ladies)';

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
(If you need to reschedule or have questions, please inform us on this number.)

અમે તમારી સેવામાં હાજર રહીશું! આભાર! 💖
''';

    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Cancel/Reject booking
  Future<void> _cancelBooking(OnlineBooking booking) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Booking / બુકિંગ રદ કરો'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Do you want to cancel booking for ${booking.customerName}?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason / વૈકલ્પિક સમય (Optional)',
                hintText: 'e.g. સ્લોટ ફુલ છે, સાંજે 5:00 વાગ્યે આવો',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go Back'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject Booking'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Update in Render Backend API & Firestore
    await FirestoreBookingService.updateStatusOnBackendApi(
      bookingId: booking.id,
      newStatus: 'Cancelled',
    );
    if (_firebaseProjectId.isNotEmpty && _firebaseProjectId != FirestoreBookingService.defaultProjectId) {
      await FirestoreBookingService.updateStatusInFirestore(
        projectId: _firebaseProjectId,
        docId: booking.id,
        newStatus: 'Cancelled',
      );
    }

    setState(() {
      final index = _bookings.indexWhere((b) => b.id == booking.id);
      if (index != -1) {
        _bookings[index] = _bookings[index].copyWith(
          status: 'Cancelled',
          notes: reasonController.text.trim().isNotEmpty
              ? 'Reason: ${reasonController.text.trim()}'
              : _bookings[index].notes,
        );
      }
    });
    await _saveBookings();

    // Send Rejection message on WhatsApp
    final phone = _cleanPhoneForWhatsApp(booking.customerPhone);
    final note = reasonController.text.trim();
    final dateFormatted = DateFormat('dd/MM/yyyy').format(booking.bookingDate);
    final parlour = widget.parlourName.isNotEmpty ? widget.parlourName : 'Nupur Beauty Parlour';

    final message = '''
🌸 *${parlour}* 🌸
નમસ્તે *${booking.customerName}* જી! 🙏

અમને જણાવતા ખેદ થાય છે કે તારીખ $dateFormatted અને સમય ${booking.timeSlot} નો સ્લોટ હાલ ઉપલબ્ધ નથી.
(We regret to inform you that your requested time slot is unavailable.)
${note.isNotEmpty ? '\n📝 *નોંધ / Note:* $note\n' : ''}
કૃપા કરીને અન્ય અનુકૂળ સમય પસંદ કરવા માટે અમારો સંપર્ક કરશો.
(Please contact us to choose an alternate time.)
📞 *સંપર્ક / Contact:* ${widget.shopPhone}
''';

    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Dialog to customize Firebase Settings
  void _showFirebaseSettingsDialog() {
    final controller = TextEditingController(text: _firebaseProjectId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cloud_sync_rounded, color: Color(0xff0369A1)),
            SizedBox(width: 8),
            Text('Firebase Sync Settings'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your Firebase Project ID to sync online bookings over internet from anywhere:',
              style: TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Firebase Project ID',
                hintText: 'e.g. parlour-management-app',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '💡 Customer requests will appear automatically here, and confirmed slots will be locked on the web form.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xff0369A1)),
            onPressed: () async {
              final newId = controller.text.trim();
              if (newId.isNotEmpty) {
                await FirestoreBookingService.saveProjectId(newId);
                setState(() => _firebaseProjectId = newId);
                Navigator.pop(ctx);
                _loadBookings();
              }
            },
            child: const Text('Save & Sync'),
          ),
        ],
      ),
    );
  }

  /// Dialog to Share Booking Link
  void _showShareLinkDialog() {
    final urlController = TextEditingController(text: _bookingWebUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.link_rounded, color: Color(0xff0369A1)),
            SizedBox(width: 8),
            Text('Online Booking Link'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this link with your customers via WhatsApp, Instagram, or Status:',
              style: TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Booking Web URL',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.language),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '💡 Customers can open this link on their mobile to enter name, number and pick an available slot.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff25d366),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final url = urlController.text.trim();
              await FirestoreBookingService.saveBookingUrl(url);
              setState(() => _bookingWebUrl = url);
              Navigator.pop(ctx);

              final text = '''
✨ *${widget.parlourName.isNotEmpty ? widget.parlourName : 'Nupur Beauty Parlour'}* ✨
નમસ્તે! હવે તમે તમારા મનપસંદ સમયે પાર્લર એપોઇન્ટમેન્ટ ઓનલાઇન બુક કરાવી શકો છો:
(Book your beauty appointment online with ease!)

🔗 *Booking Link:* $url

✨ સર્વિસ અને અનુકૂળ ટાઇમ સ્લોટ પસંદ કરીને બુક કરો! 💅🌸
''';
              final uri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Share on WhatsApp'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Sync appointments created by Mummy in the app to the website so those slots show Already Booked
  Future<void> _syncAppAppointmentsToWebsite() async {
    final list = widget.existingAppointments;
    if (list == null || list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('કોઈ એપોઇન્ટમેન્ટ મળી નથી (No appointments in app to sync)'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    int syncedCount = 0;

    for (final appt in list) {
      final date = appt['date'] as DateTime?;
      final slot = appt['timeSlot'] as String?;
      final name = appt['customerName'] as String? ?? 'Client';
      final service = appt['serviceName'] as String? ?? 'Parlour Service';

      if (date == null || slot == null || slot.isEmpty) continue;

      // Filter only today or upcoming
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final apptDate = DateTime(date.year, date.month, date.day);
      if (apptDate.isBefore(today)) continue;

      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      // Check if already in _bookings
      final alreadyExists = _bookings.any(
        (b) =>
            DateFormat('yyyy-MM-dd').format(b.bookingDate) == dateStr &&
            b.timeSlot.trim().toLowerCase() == slot.trim().toLowerCase() &&
            b.status != 'Cancelled',
      );

      if (!alreadyExists) {
        final newBooking = OnlineBooking(
          id: 'app_mummy_${DateTime.now().millisecondsSinceEpoch}_$syncedCount',
          bookingRef: 'NP-${100000 + (syncedCount * 137 % 900000)}',
          customerName: name,
          customerPhone: '',
          serviceNames: service,
          totalAmount: 0.0,
          bookingDate: date,
          timeSlot: slot,
          status: 'Confirmed', // Confirmed marks the slot as Already Booked on the website!
          createdAt: DateTime.now(),
          notes: 'Booked directly by Mummy in parlour app',
        );

        if (_firebaseProjectId.isNotEmpty) {
          try {
            await FirestoreBookingService.createBookingInFirestore(
              projectId: _firebaseProjectId,
              booking: newBooking,
            );
          } catch (_) {}
        }

        _bookings.add(newBooking);
        syncedCount++;
      }
    }

    await _saveBookings();
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            syncedCount > 0
                ? '✅ $syncedCount એપોઇન્ટમેન્ટ વેબસાઇટ પર લૉક થઈ ગઈ! (Slots marked Already Booked on website)'
                : '✅ તમામ એપોઇન્ટમેન્ટ પહેલેથી જ વેબસાઇટ પર લૉક છે.',
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _bookings.where((b) => b.status == 'Pending').length;
    final filtered = _bookings.where((b) {
      if (_selectedFilter == 'All') return true;
      return b.status.toLowerCase() == _selectedFilter.toLowerCase();
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Online Bookings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'ઓનલાઇન સ્લોટ બુકિંગ રિક્વેસ્ટ',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sync Mummy Appointments to Website (સ્લોટ લૉક કરો)',
            icon: const Icon(Icons.cloud_upload_rounded, color: Color(0xff0369A1)),
            onPressed: _syncAppAppointmentsToWebsite,
          ),
          IconButton(
            tooltip: 'Firebase Settings',
            icon: const Icon(Icons.cloud_sync_rounded, color: Color(0xff0369A1)),
            onPressed: _showFirebaseSettingsDialog,
          ),
          IconButton(
            tooltip: 'Share Link',
            icon: const Icon(Icons.share_rounded, color: Color(0xff0369A1)),
            onPressed: _showShareLinkDialog,
          ),
          IconButton(
            tooltip: 'Refresh / Sync',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadBookings,
          ),
        ],
      ),
      body: Column(
        children: [
          // Pending banner if any requests exist
          if (pendingCount > 0)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade400, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.notification_important_rounded,
                      color: Colors.amber.shade800, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔔 $pendingCount નવી બુકિંગ વિનંતીઓ પેન્ડિંગ છે!',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                            fontSize: 13,
                          ),
                        ),
                        const Text(
                          'ટેપ કરીને તપાસો અને ગ્રાહકને કન્ફર્મ કરો',
                          style: TextStyle(fontSize: 11.5, color: Colors.black54),
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
                      final firstPending =
                          _bookings.firstWhere((b) => b.status == 'Pending');
                      _showConfirmationRequestDialog(firstPending);
                    },
                    child: const Text('Review', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Filters
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).cardColor,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('Pending', 'Pending ($pendingCount)',
                      isUrgent: pendingCount > 0),
                  const SizedBox(width: 8),
                  _buildFilterChip('Confirmed', 'Confirmed'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Cancelled', 'Cancelled'),
                  const SizedBox(width: 8),
                  _buildFilterChip('All', 'All Bookings'),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // Main list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_available_rounded,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No ${_selectedFilter == 'Pending' ? 'Pending' : ''} bookings found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xff0369A1),
                              ),
                              onPressed: _showShareLinkDialog,
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('Share Booking Link'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return _buildBookingCard(item);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filter, String label, {bool isUrgent = false}) {
    final isSelected = _selectedFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = filter),
      selectedColor: const Color(0xff0369A1).withOpacity(0.18),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? const Color(0xff0369A1) : const Color(0xffCBD5E1),
        width: isSelected ? 1.5 : 1,
      ),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xff0369A1) : const Color(0xff334155),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        fontSize: 13,
      ),
    );
  }

  Widget _buildBookingCard(OnlineBooking item) {
    final isPending = item.status == 'Pending';
    final isConfirmed = item.status == 'Confirmed';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPending
              ? Colors.amber.shade400
              : (isConfirmed ? Colors.green.shade400 : const Color(0xffCBD5E1)),
          width: isPending ? 1.8 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isPending ? () => _showConfirmationRequestDialog(item) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xff0369A1).withOpacity(0.12),
                          child: Text(
                            item.customerName.isNotEmpty
                                ? item.customerName.substring(0, 1).toUpperCase()
                                : 'C',
                            style: const TextStyle(
                              color: Color(0xff0369A1),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.customerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '📱 ${item.customerPhone} • #${item.bookingRef}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildStatusBadge(item.status),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xffF0F7FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xff0369A1).withOpacity(0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.auto_awesome, size: 15, color: Color(0xff0369A1)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.serviceNames,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded,
                                size: 14, color: Color(0xff64748B)),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('dd MMM yyyy').format(item.bookingDate),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12.5),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 14, color: Color(0xff64748B)),
                            const SizedBox(width: 4),
                            Text(
                              item.timeSlot,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xff0369A1),
                                  fontSize: 12.5),
                            ),
                          ],
                        ),
                        Text(
                          '₹${item.totalAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xff0369A1),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (item.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_note_rounded, size: 16, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.notes,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Material(
                    color: Colors.blue.withOpacity(0.1),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () async {
                        final uri = Uri.parse('tel:${item.customerPhone}');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(9),
                        child: Icon(Icons.call_rounded, color: Colors.blue, size: 19),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: const Color(0xff25D366).withOpacity(0.12),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () async {
                        final phone = _cleanPhoneForWhatsApp(item.customerPhone);
                        final uri = Uri.parse('https://wa.me/$phone');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(9),
                        child: Icon(Icons.chat_bubble_rounded,
                            color: Color(0xff25D366), size: 19),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isPending) ...[
                    Expanded(
                      flex: 4,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade600,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _cancelBooking(item),
                        child: const Text('Reject',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 5,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff0369A1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _confirmBooking(item),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                        label: const Text('Confirm',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ] else if (isConfirmed) ...[
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          foregroundColor: const Color(0xff25D366),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _sendBilingualWhatsAppConfirmation(item),
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Resend WhatsApp',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12.5)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String text;

    switch (status.toLowerCase()) {
      case 'confirmed':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        text = '✅ Confirmed';
        break;
      case 'cancelled':
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        text = '❌ Cancelled';
        break;
      default:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        text = '⏳ Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
