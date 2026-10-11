const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 10000;

// Middleware
app.use(cors({ origin: '*' }));
app.use(express.json());

// Path to data file
const DATA_DIR = path.join(__dirname, 'data');
const DATA_FILE = path.join(DATA_DIR, 'bookings.json');

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Initial seed data including the booking from user's test
const INITIAL_BOOKINGS = [
  {
    id: "NP-701664",
    bookingRef: "NP-701664",
    customerName: "Jash Godhasara",
    customerPhone: "9427451121",
    serviceNames: "Festive Golden Glow Package (Facial + D-Tan + Wax + Threading), Festive Party Makeup & Hair Styling Combo, Hair Spa + Herbal Cleanup + Manicure Combo",
    totalAmount: 4497,
    bookingDate: "2026-10-10",
    timeSlot: "12:00 PM",
    status: "Pending",
    notes: "",
    createdAt: "2026-10-10T12:20:00.000Z"
  }
];

// Helper to load bookings
function loadBookings() {
  try {
    if (fs.existsSync(DATA_FILE)) {
      const content = fs.readFileSync(DATA_FILE, 'utf8');
      if (content.trim()) {
        const list = JSON.parse(content);
        if (Array.isArray(list) && list.length > 0) {
          return list;
        }
      }
    }
  } catch (err) {
    console.error("Error loading bookings from file:", err);
  }
  // Initialize with seed data
  saveBookings(INITIAL_BOOKINGS);
  return INITIAL_BOOKINGS;
}

// Helper to save bookings
function saveBookings(bookings) {
  try {
    fs.writeFileSync(DATA_FILE, JSON.stringify(bookings, null, 2), 'utf8');
  } catch (err) {
    console.error("Error saving bookings to file:", err);
  }
}

// In-memory cache synced with disk
let bookings = loadBookings();

// App appointment locked slots store (date -> array of slots)
const appLockedSlots = {};

// ---------------- API ENDPOINTS ---------------- //

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString(), bookingsCount: bookings.length });
});

// GET /api/bookings - Get all bookings (optional filter by ?date=YYYY-MM-DD or ?status=Pending)
app.get('/api/bookings', (req, res) => {
  const { date, status } = req.query;
  let results = [...bookings];

  if (date) {
    results = results.filter(b => b.bookingDate === date);
  }
  if (status) {
    results = results.filter(b => b.status.toLowerCase() === status.toLowerCase());
  }

  // Sort descending by creation date
  results.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));

  res.json(results);
});

// POST /api/bookings - Create new online booking request
app.post('/api/bookings', (req, res) => {
  const data = req.body;
  if (!data || !data.customerName || !data.bookingDate || !data.timeSlot) {
    return res.status(400).json({ error: 'Missing required booking fields' });
  }

  const id = data.id || data.bookingRef || `NP-${Math.floor(100000 + Math.random() * 900000)}`;
  const newBooking = {
    id: id,
    bookingRef: data.bookingRef || id,
    customerName: data.customerName.trim(),
    customerPhone: (data.customerPhone || '').trim(),
    serviceNames: data.serviceNames || 'General Parlour Service',
    totalAmount: Number(data.totalAmount) || 0,
    bookingDate: data.bookingDate, // format: YYYY-MM-DD
    timeSlot: data.timeSlot.trim(),
    status: data.status || 'Pending',
    notes: data.notes || '',
    createdAt: data.createdAt || new Date().toISOString()
  };

  // Check if slot is already confirmed or pending
  const existingActive = bookings.find(
    b => b.bookingDate === newBooking.bookingDate &&
         b.timeSlot === newBooking.timeSlot &&
         b.status !== 'Cancelled' &&
         b.id !== newBooking.id
  );

  if (existingActive) {
    return res.status(409).json({
      error: `Slot ${newBooking.timeSlot} on ${newBooking.bookingDate} is already reserved.`
    });
  }

  // Check if already in list by id
  const existingIdx = bookings.findIndex(b => b.id === newBooking.id);
  if (existingIdx >= 0) {
    bookings[existingIdx] = newBooking;
  } else {
    bookings.push(newBooking);
  }

  saveBookings(bookings);
  console.log(`[BOOKING CREATED] #${newBooking.bookingRef} for ${newBooking.customerName} on ${newBooking.bookingDate} at ${newBooking.timeSlot}`);

  res.status(201).json({ success: true, booking: newBooking });
});

// PATCH or POST /api/bookings/:id/status - Update booking status ('Confirmed' or 'Cancelled')
function handleStatusUpdate(req, res) {
  const { id } = req.params;
  const status = req.body.status || req.query.status;

  if (!status) {
    return res.status(400).json({ error: 'Status is required (Confirmed or Cancelled)' });
  }

  const booking = bookings.find(b => b.id === id || b.bookingRef === id);
  if (!booking) {
    return res.status(404).json({ error: 'Booking not found' });
  }

  booking.status = status;
  if (req.body.notes) {
    booking.notes = req.body.notes;
  }

  saveBookings(bookings);
  console.log(`[BOOKING STATUS UPDATED] #${booking.bookingRef} -> ${status}`);

  res.json({ success: true, booking });
}

app.patch('/api/bookings/:id', handleStatusUpdate);
app.patch('/api/bookings/:id/status', handleStatusUpdate);
app.post('/api/bookings/:id/status', handleStatusUpdate);

// GET /api/slots?date=YYYY-MM-DD - Get list of booked / locked slots for a given date
app.get('/api/slots', (req, res) => {
  const { date } = req.query;
  if (!date) {
    return res.status(400).json({ error: 'Query parameter date=YYYY-MM-DD is required' });
  }

  const bookedSlots = new Set();

  // 1. From online bookings (status not Cancelled)
  bookings.forEach(b => {
    if (b.bookingDate === date && b.status !== 'Cancelled' && b.timeSlot) {
      bookedSlots.add(b.timeSlot.trim());
    }
  });

  // 2. From app manual locked slots
  if (appLockedSlots[date]) {
    appLockedSlots[date].forEach(s => bookedSlots.add(s.trim()));
  }

  res.json({
    date,
    bookedSlots: Array.from(bookedSlots)
  });
});

// POST /api/sync-app-appointments - Flutter app sends appointments to lock on web
app.post('/api/sync-app-appointments', (req, res) => {
  const { appointments } = req.body;
  if (Array.isArray(appointments)) {
    appointments.forEach(item => {
      const date = item.date; // YYYY-MM-DD
      const slot = item.timeSlot; // e.g. "10:30 AM"
      if (date && slot) {
        if (!appLockedSlots[date]) appLockedSlots[date] = new Set();
        appLockedSlots[date].add(slot.trim());
      }
    });
  }
  res.json({ success: true, message: 'App appointments synced to website slots.' });
});

// Download updated Android APK directly from phone browser
app.get('/download', (req, res) => {
  const apkPath = path.join(__dirname, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
  if (fs.existsSync(apkPath)) {
    res.download(apkPath, 'parlour_management_app.apk');
  } else {
    res.status(404).send('APK not found. Please build release APK.');
  }
});

app.get('/app.apk', (req, res) => {
  const apkPath = path.join(__dirname, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
  if (fs.existsSync(apkPath)) {
    res.download(apkPath, 'parlour_management_app.apk');
  } else {
    res.status(404).send('APK not found.');
  }
});

// Serve frontend static files
app.use(express.static(path.join(__dirname, 'online_booking_web')));

// Catch-all to serve index.html for frontend routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'online_booking_web', 'index.html'));
});

// Start Server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Nupur Beauty Parlour server running on http://0.0.0.0:${PORT}`);
  console.log(`📡 Bookings API available at /api/bookings`);
});
