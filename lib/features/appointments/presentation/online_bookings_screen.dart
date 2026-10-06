import 'dart:convert';
import 'package:flutter/material.dart';
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

class OnlineBookingsScreen extends StatefulWidget {
  const OnlineBookingsScreen({
    super.key,
    required this.parlourName,
    required this.shopPhone,
    required this.shopAddress,
    required this.onAddConfirmedAppointment,
  });

  final String parlourName;
  final String shopPhone;
  final String shopAddress;
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

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_storageKey);

    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(rawJson) as List<dynamic>;
        _bookings = list
            .map((item) => OnlineBooking.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Error decoding bookings: $e');
      }
    }

    if (_bookings.isEmpty) {
      _bookings = [
        OnlineBooking(
          id: 'ob_01',
          bookingRef: 'NP-582910',
          customerName: 'Pooja Patel',
          customerPhone: '9876543210',
          serviceNames: 'Diwali Golden Glow Package (Facial + D-Tan + Wax), Hair Spa',
          totalAmount: 2149.0,
          bookingDate: DateTime.now().add(const Duration(days: 1)),
          timeSlot: '10:30 AM',
          status: 'Pending',
          createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
          notes: 'Festive party makeup inquiry as well.',
        ),
        OnlineBooking(
          id: 'ob_02',
          bookingRef: 'NP-819324',
          customerName: 'Dhara Shah',
          customerPhone: '9123456780',
          serviceNames: 'Gold Facial, Eyebrow & Upper Lip, Festive Mehendi',
          totalAmount: 1420.0,
          bookingDate: DateTime.now().add(const Duration(days: 2)),
          timeSlot: '03:30 PM',
          status: 'Pending',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          notes: 'Please keep slot sharp at 3:30 PM.',
        ),
      ];
      await _saveBookings();
    }

    if (mounted) {
      setState(() => _isLoading = false);
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

  Future<void> _confirmBooking(OnlineBooking booking) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 8),
            Text('Confirm Booking'),
          ],
        ),
        content: Text(
          'Confirm booking for ${booking.customerName}?\n\n'
          '📅 Date: ${DateFormat('dd-MMM-yyyy').format(booking.bookingDate)}\n'
          '⏰ Time: ${booking.timeSlot}\n'
          '💅 Services: ${booking.serviceNames}\n\n'
          'Confirming will add this appointment and open WhatsApp to send confirmation message.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff0369A1),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Confirm & WhatsApp'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final timeOfDay = _parseTimeOfDay(booking.timeSlot);
    await widget.onAddConfirmedAppointment(
      customerName: booking.customerName,
      customerPhone: booking.customerPhone,
      serviceName: booking.serviceNames,
      date: booking.bookingDate,
      time: timeOfDay,
      amount: booking.totalAmount,
    );

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
        content: Text('✅ Booking confirmed for ${booking.customerName}!'),
        backgroundColor: Colors.green.shade700,
      ),
    );

    _sendWhatsAppConfirmation(booking);
  }

  Future<void> _sendWhatsAppConfirmation(OnlineBooking booking) async {
    final phone = _cleanPhoneForWhatsApp(booking.customerPhone);
    final dateFormatted = DateFormat('dd/MM/yyyy').format(booking.bookingDate);

    final message = '''
🌸 *${widget.parlourName.isNotEmpty ? widget.parlourName : 'Nupur Beauty Parlour'}* 🌸
Hello *${booking.customerName}*! ✨

Your festive booking is *CONFIRMED*. 🪔

📋 *Booking ID:* #${booking.bookingRef}
📅 *Date:* $dateFormatted
⏰ *Time:* ${booking.timeSlot}
💅 *Services:* ${booking.serviceNames}
💰 *Estimated Amount:* ₹${booking.totalAmount.toStringAsFixed(0)}

📍 *Address:* ${widget.shopAddress.isNotEmpty ? widget.shopAddress : 'Nupur Beauty Parlour'}
📞 *Contact:* ${widget.shopPhone}

We look forward to welcoming you! Have a wonderful day. 🙏
''';

    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _cancelBooking(OnlineBooking booking) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject / Cancel Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cancel booking for ${booking.customerName}?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason / Alternate Time (Optional)',
                hintText: 'e.g. Slot is full, please visit at 5:00 PM',
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

    final phone = _cleanPhoneForWhatsApp(booking.customerPhone);
    final note = reasonController.text.trim();
    final message = '''
🌸 *${widget.parlourName.isNotEmpty ? widget.parlourName : 'Nupur Beauty Parlour'}* 🌸
Hello *${booking.customerName}*,

We regret to inform you that your requested time slot on ${DateFormat('dd/MM/yyyy').format(booking.bookingDate)} at ${booking.timeSlot} is currently unavailable.
${note.isNotEmpty ? '\n📝 *Note:* $note\n' : ''}
Please contact us to choose an alternate time.
📞 *Contact:* ${widget.shopPhone}
''';

    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showShareLinkDialog() {
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
              'Share this link with your customers via WhatsApp, Instagram, or Status for online bookings:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const SelectableText(
                'http://192.168.1.11/dipa/parlour_management_app/online_booking_web/',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xff0369A1),
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '💡 Customers can open this link on their mobile and book instantly.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
              Navigator.pop(ctx);
              final text = '''
✨ *Nupur Beauty Parlour - Festive & Diwali Booking* 🪔
Book your preferred slot & festive beauty package online:

🔗 Booking Link: http://192.168.1.11/dipa/parlour_management_app/online_booking_web/

Special festive packages & offers available! 💅🌸
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
              'Requests from online booking web form',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share Link',
            icon: const Icon(Icons.share_rounded, color: Color(0xff0369A1)),
            onPressed: _showShareLinkDialog,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadBookings,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).cardColor,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('Pending', 'Pending (${pendingCount})', isUrgent: pendingCount > 0),
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
              ? const Color(0xff38BDF8).withOpacity(0.7)
              : (isConfirmed ? Colors.green.shade400 : const Color(0xffCBD5E1)),
          width: isPending ? 1.5 : 1,
        ),
      ),
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
                          const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xff64748B)),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('dd MMM yyyy').format(item.bookingDate),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 14, color: Color(0xff64748B)),
                          const SizedBox(width: 4),
                          Text(
                            item.timeSlot,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
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
                      child: Icon(Icons.chat_bubble_rounded, color: Color(0xff25D366), size: 19),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _cancelBooking(item),
                      child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _confirmBooking(item),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                      label: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ] else if (isConfirmed) ...[
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        foregroundColor: const Color(0xff25D366),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _sendWhatsAppConfirmation(item),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Resend WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    ),
                  ),
                ],
              ],
            ),
          ],
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
