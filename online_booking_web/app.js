// Services Catalog
const PARLOUR_SERVICES = [
  {
    category: "✨ Festive Special Packages (વિશેષ પેકેજ)",
    items: [
      { id: "pkg_glow", name: "Festive Golden Glow Package (Facial + D-Tan + Wax + Threading)", price: 1499, duration: "90 min" },
      { id: "pkg_bridal", name: "Festive Party Makeup & Hair Styling Combo", price: 1999, duration: "120 min" },
      { id: "pkg_hair_spa", name: "Hair Spa + Herbal Cleanup + Manicure Combo", price: 999, duration: "75 min" }
    ]
  },
  {
    category: "💇‍♀️ Hair Services & Treatments (હેર સર્વિસ)",
    items: [
      { id: "hair_cut", name: "Hair Cut & Styling", price: 250, duration: "30 min" },
      { id: "hair_spa", name: "L'Oreal Hair Spa", price: 650, duration: "45 min" },
      { id: "hair_color", name: "Hair Color / Root Touch-up", price: 500, duration: "60 min" },
      { id: "hair_straightening", name: "Hair Smoothening / Keratin Treatment", price: 2499, duration: "180 min" }
    ]
  },
  {
    category: "✨ Skin Care & Facials (ફેસિયલ અને સ્કિન કેર)",
    items: [
      { id: "facial_gold", name: "Gold / Diamond Glow Facial", price: 850, duration: "50 min" },
      { id: "facial_clean", name: "Fruit / Herbal Cleanup", price: 400, duration: "35 min" },
      { id: "dtan_pack", name: "D-Tan Face & Neck Glow Pack", price: 300, duration: "25 min" },
      { id: "hydra_facial", name: "Hydra Deep Glow Facial", price: 1200, duration: "60 min" }
    ]
  },
  {
    category: "💅 Waxing & Threading (વેક્સિંગ અને થ્રેડીંગ)",
    items: [
      { id: "threading_eyebrow", name: "Eyebrow & Upper Lip Threading", price: 70, duration: "15 min" },
      { id: "wax_full_hand_leg", name: "Full Hands & Half Legs Honey Waxing", price: 450, duration: "40 min" },
      { id: "wax_rica", name: "Rica Brazilian / White Chocolate Waxing", price: 750, duration: "45 min" }
    ]
  },
  {
    category: "🌿 Makeup & Mehendi (મેકઅપ અને મહેંદી)",
    items: [
      { id: "party_makeup", name: "HD Festive Party Makeup", price: 1200, duration: "60 min" },
      { id: "mehendi_hands", name: "Festive Designer Mehendi (Both Hands)", price: 500, duration: "45 min" }
    ]
  }
];

// Standard Salon Time Slots
const TIME_SLOTS = [
  { id: "09:00 AM", label: "09:00 AM", period: "Morning" },
  { id: "10:30 AM", label: "10:30 AM", period: "Morning" },
  { id: "12:00 PM", label: "12:00 PM", period: "Afternoon" },
  { id: "02:00 PM", label: "02:00 PM", period: "Afternoon" },
  { id: "03:30 PM", label: "03:30 PM", period: "Afternoon" },
  { id: "05:00 PM", label: "05:00 PM", period: "Evening" },
  { id: "06:30 PM", label: "06:30 PM", period: "Evening" },
  { id: "08:00 PM", label: "08:00 PM", period: "Night" }
];

// Parlour contact for direct WhatsApp message
const PARLOUR_WHATSAPP_NUMBER = "919427451121";

// Global Cloud Storage URL for instant 24/7 internet sync
const CLOUD_STORAGE_URL = "https://api.restful-api.dev/objects/ff808181a09d98f701a124c3537f33ed";

// Live Backend API base URL (Render or Local)
const API_BASE_URL = (typeof window !== "undefined" && (window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1"))
  ? ""
  : (typeof window !== "undefined" && window.location.origin.includes("onrender.com") ? window.location.origin : "https://nupur-beauty-parlour.onrender.com");

let selectedServices = [];
let selectedSlot = "";
let currentBookedSlots = [];
let lastBookingData = null;

// Initialize form
document.addEventListener("DOMContentLoaded", () => {
  renderServices();
  setupDateLimits();
  setupSlotListeners();
  setupFormListener();
});

// Set minimum date to today and listen for changes
function setupDateLimits() {
  const dateInput = document.getElementById("bookingDate");
  const today = new Date().toISOString().split("T")[0];
  dateInput.min = today;
  dateInput.value = today;

  dateInput.addEventListener("change", () => {
    selectedSlot = "";
    document.getElementById("timeSlot").value = "";
    checkAndRenderSlotsForDate(dateInput.value);
  });

  // Initial slot load for today
  checkAndRenderSlotsForDate(today);
}

// Render categorized services
function renderServices() {
  const container = document.getElementById("servicesContainer");
  container.innerHTML = "";

  PARLOUR_SERVICES.forEach((cat) => {
    const catEl = document.createElement("div");
    catEl.className = "service-category";

    const titleEl = document.createElement("div");
    titleEl.className = "cat-title";
    titleEl.textContent = cat.category;
    catEl.appendChild(titleEl);

    const listEl = document.createElement("div");
    listEl.className = "services-list";

    cat.items.forEach((item) => {
      const itemEl = document.createElement("div");
      itemEl.className = "service-item";
      itemEl.dataset.id = item.id;

      itemEl.innerHTML = `
        <input type="checkbox" id="svc_${item.id}" value="${item.id}">
        <div class="service-info">
          <div class="service-name">${item.name}</div>
          <div class="service-price">₹${item.price} <span class="service-duration">(${item.duration})</span></div>
        </div>
      `;

      itemEl.addEventListener("click", (e) => {
        if (e.target.tagName !== "INPUT") {
          const checkbox = itemEl.querySelector("input");
          checkbox.checked = !checkbox.checked;
        }
        toggleService(item, itemEl.querySelector("input").checked);
        itemEl.classList.toggle("active", itemEl.querySelector("input").checked);
      });

      listEl.appendChild(itemEl);
    });

    catEl.appendChild(listEl);
    container.appendChild(catEl);
  });
}

function toggleService(item, isChecked) {
  if (isChecked) {
    if (!selectedServices.some(s => s.id === item.id)) {
      selectedServices.push(item);
    }
  } else {
    selectedServices = selectedServices.filter(s => s.id !== item.id);
  }
  updateSummary();
}

function updateSummary() {
  const summaryBox = document.getElementById("selectedSummary");
  const countEl = document.getElementById("selectedCount");
  const totalEl = document.getElementById("selectedTotal");

  if (selectedServices.length > 0) {
    summaryBox.style.display = "flex";
    countEl.textContent = selectedServices.length;
    const total = selectedServices.reduce((sum, s) => sum + s.price, 0);
    totalEl.textContent = `₹${total}`;
  } else {
    summaryBox.style.display = "none";
  }
}

// Fetch booked slots from live Backend API, Firebase Firestore, or Local fallback
async function fetchBookedSlots(dateStr) {
  const bookedSlots = [];

  // 1. Fetch from Global Cloud Store (instant 24/7 internet sync)
  try {
    const cRes = await fetch(CLOUD_STORAGE_URL);
    if (cRes.ok) {
      const cData = await cRes.json();
      if (cData && cData.data && Array.isArray(cData.data.bookings)) {
        cData.data.bookings.forEach(b => {
          if (b.bookingDate === dateStr && b.status !== "Cancelled" && b.timeSlot) {
            const s = b.timeSlot.trim();
            if (!bookedSlots.includes(s)) bookedSlots.push(s);
          }
        });
        console.log(`Fetched ${bookedSlots.length} booked slots from Global Cloud Store for ${dateStr}`);
      }
    }
  } catch (e) {
    console.warn("Cloud slot fetch error:", e);
  }

  // 2. Fetch from live Backend API (Render / Local)
  try {
    const res = await fetch(`${API_BASE_URL}/api/slots?date=${encodeURIComponent(dateStr)}`);
    if (res.ok) {
      const data = await res.json();
      if (data && Array.isArray(data.bookedSlots)) {
        data.bookedSlots.forEach(s => {
          if (s && !bookedSlots.includes(s.trim())) {
            bookedSlots.push(s.trim());
          }
        });
      }
    }
  } catch (e) {
    console.warn("Backend API slot fetch error:", e);
  }

  // 2. If Firebase Firestore is active
  if (db && isFirebaseActive) {
    try {
      const snapshot = await db.collection("online_bookings")
        .where("bookingDate", "==", dateStr)
        .get();

      snapshot.forEach(doc => {
        const data = doc.data();
        // Slots with 'Pending' or 'Confirmed' are considered booked/reserved
        // Only 'Cancelled' slots are released and available
        if (data.status !== "Cancelled" && data.timeSlot) {
          const s = data.timeSlot.trim();
          if (!bookedSlots.includes(s)) bookedSlots.push(s);
        }
      });
      console.log(`Fetched ${bookedSlots.length} booked slots from Firestore for ${dateStr}:`, bookedSlots);
    } catch (e) {
      console.error("Firestore error while fetching booked slots:", e);
    }
  }

  // 3. Fallback to localStorage bookings
  try {
    const raw = localStorage.getItem("nupur_bookings");
    if (raw) {
      const list = JSON.parse(raw);
      list.forEach(b => {
        if (b.bookingDate === dateStr && b.status !== "Cancelled" && b.timeSlot) {
          const s = b.timeSlot.trim();
          if (!bookedSlots.includes(s)) bookedSlots.push(s);
        }
      });
    }
  } catch (e) {
    console.warn("Could not read local bookings:", e);
  }

  return bookedSlots;
}

// Check and render slots for selected date
async function checkAndRenderSlotsForDate(dateStr) {
  const statusBox = document.getElementById("slotStatusBox");
  const statusText = document.getElementById("slotStatusText");
  const grid = document.getElementById("slotsGrid");

  statusBox.className = "slot-status-box loading";
  statusText.innerHTML = `<span>⏳ Checking slots for ${formatDateDisplay(dateStr)}...</span>`;

  try {
    currentBookedSlots = await fetchBookedSlots(dateStr);
    renderSlotsGrid(currentBookedSlots);

    const availableCount = TIME_SLOTS.length - currentBookedSlots.length;
    if (availableCount <= 0) {
      statusBox.className = "slot-status-box all-booked";
      statusText.innerHTML = `<span>❌ All slots booked for ${formatDateDisplay(dateStr)}. Please select another date.</span>`;
    } else {
      statusBox.className = "slot-status-box";
      statusText.innerHTML = `<span>✅ <strong>${availableCount} Slots Available</strong> (${currentBookedSlots.length} Booked)</span>`;
    }
  } catch (err) {
    console.error("Error loading slots:", err);
    renderSlotsGrid([]);
    statusBox.className = "slot-status-box";
    statusText.innerHTML = `<span>⚡ Slots ready for booking</span>`;
  }
}

// Render the interactive Slot buttons
function renderSlotsGrid(bookedSlots) {
  const grid = document.getElementById("slotsGrid");
  const hiddenSelect = document.getElementById("timeSlot");

  grid.innerHTML = "";
  hiddenSelect.innerHTML = `<option value="" disabled selected>Select Time Slot</option>`;

  TIME_SLOTS.forEach((slot) => {
    const isBooked = bookedSlots.includes(slot.label);
    const isSelected = selectedSlot === slot.label;

    // Build select option
    const opt = document.createElement("option");
    opt.value = slot.label;
    opt.textContent = `${slot.label} ${isBooked ? '(Already Booked)' : '(Free Slot)'}`;
    opt.disabled = isBooked;
    hiddenSelect.appendChild(opt);

    // Build interactive slot card
    const card = document.createElement("div");
    card.className = `slot-card ${isBooked ? 'disabled booked' : 'available'} ${isSelected ? 'selected' : ''}`;
    card.dataset.time = slot.label;

    if (isBooked) {
      card.innerHTML = `
        <span class="slot-time">${slot.label}</span>
        <span class="slot-badge">Already Booked 🔒</span>
        <span class="slot-sub-text">પહેલેથી બુક થયેલ</span>
      `;
    } else {
      card.innerHTML = `
        <span class="slot-time">${slot.label}</span>
        <span class="slot-badge">${isSelected ? 'Selected ✨' : 'Free Slot ✨'}</span>
        <span class="slot-sub-text">${isSelected ? 'પસંદ કરેલ' : 'ઉપલબ્ધ'}</span>
      `;

      card.addEventListener("click", () => {
        selectSlot(slot.label);
      });
    }

    grid.appendChild(card);
  });
}

function selectSlot(time) {
  selectedSlot = time;
  document.getElementById("timeSlot").value = time;

  // Re-highlight cards
  const cards = document.querySelectorAll(".slot-card");
  cards.forEach(card => {
    if (card.classList.contains("disabled")) return;
    const badge = card.querySelector(".slot-badge");
    const sub = card.querySelector(".slot-sub-text");
    if (card.dataset.time === time) {
      card.classList.add("selected");
      if (badge) badge.textContent = "Selected ✨";
      if (sub) sub.textContent = "પસંદ કરેલ";
    } else {
      card.classList.remove("selected");
      if (badge) badge.textContent = "Free Slot ✨";
      if (sub) sub.textContent = "ઉપલબ્ધ";
    }
  });
}

function setupSlotListeners() {
  const hiddenSelect = document.getElementById("timeSlot");
  hiddenSelect.addEventListener("change", (e) => {
    selectSlot(e.target.value);
  });
}

function formatDateDisplay(dateStr) {
  try {
    const d = new Date(dateStr);
    return d.toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
  } catch (_) {
    return dateStr;
  }
}

// Form submit handler
function setupFormListener() {
  const form = document.getElementById("bookingForm");
  const submitBtn = document.getElementById("submitBtn");

  form.addEventListener("submit", async (e) => {
    e.preventDefault();

    const name = document.getElementById("custName").value.trim();
    const phone = document.getElementById("custPhone").value.trim();
    const date = document.getElementById("bookingDate").value;
    const time = selectedSlot || document.getElementById("timeSlot").value;
    const notes = document.getElementById("notes").value.trim();

    if (!name || !phone || !date) {
      alert("Please fill in all required fields.");
      return;
    }

    if (!time) {
      alert("કૃપા કરીને સ્લોટ પસંદ કરો. (Please select an available time slot.)");
      return;
    }

    // Double check that chosen slot isn't already booked
    if (currentBookedSlots.includes(time)) {
      alert(`દુર્ભાગ્યે આ સ્લોટ (${time}) હમણાં જ બુક થઈ ગયો છે. કૃપા કરીને અન્ય સ્લોટ પસંદ કરો.\n(Sorry, this slot is already booked. Please choose another slot.)`);
      checkAndRenderSlotsForDate(date);
      return;
    }

    if (selectedServices.length === 0) {
      alert("કૃપા કરીને ઓછામાં ઓછી એક સર્વિસ પસંદ કરો. (Please select at least one service.)");
      return;
    }

    const totalAmount = selectedServices.reduce((sum, s) => sum + s.price, 0);
    const serviceNames = selectedServices.map(s => s.name).join(", ");
    const bookingRef = "NP-" + Math.floor(100000 + Math.random() * 900000);

    const bookingData = {
      id: bookingRef,
      bookingRef,
      customerName: name,
      customerPhone: phone,
      services: selectedServices.map(s => ({ id: s.id, name: s.name, price: s.price })),
      serviceNames: serviceNames,
      totalAmount: totalAmount,
      bookingDate: date,
      timeSlot: time,
      notes: notes,
      status: "Pending", // Pending, Confirmed, Cancelled
      createdAt: new Date().toISOString(),
      timestamp: Date.now()
    };

    lastBookingData = bookingData;
    submitBtn.disabled = true;
    submitBtn.innerHTML = `<span>⏳</span> વિનંતી મોકલાઈ રહી છે... (Submitting...)`;

    try {
      // 1. Upload to Global Cloud Storage (works 24/7 everywhere across internet)
      try {
        const getRes = await fetch(CLOUD_STORAGE_URL, { cache: "no-store" });
        if (getRes.ok) {
          const cloudData = await getRes.json();
          const list = (cloudData && cloudData.data && Array.isArray(cloudData.data.bookings))
            ? cloudData.data.bookings
            : [];
          const existingIdx = list.findIndex(b => (b.id && b.id === bookingData.id) || (b.bookingRef && b.bookingRef === bookingData.bookingRef));
          if (existingIdx >= 0) list[existingIdx] = bookingData;
          else list.unshift(bookingData);

          await fetch(CLOUD_STORAGE_URL, {
            method: "PUT",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ name: "nupur_bookings", data: { bookings: list } })
          });
          console.log("✅ Booking uploaded to Global Cloud Store!");
        }
      } catch (cloudErr) {
        console.warn("Global Cloud sync error:", cloudErr);
      }

      // 2. Submit to Backend REST API (Render / Express / Local)
      try {
        const apiRes = await fetch(`${API_BASE_URL}/api/bookings`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(bookingData)
        });
        if (apiRes.ok) {
          const resJson = await apiRes.json();
          if (resJson && resJson.booking && resJson.booking.id) {
            bookingData.id = resJson.booking.id;
          }
          console.log("✅ Booking successfully saved to Backend API:", bookingData.id);
        }
      } catch (apiErr) {
        console.warn("Failed to post to backend API:", apiErr);
      }

      // 3. Write to Firestore if connected
      if (db && isFirebaseActive) {
        const docRef = await db.collection("online_bookings").add(bookingData);
        bookingData.id = docRef.id;
        console.log("Booking successfully added to Firestore with ID:", docRef.id);
      }

      // 3. Also cache in localStorage
      const existing = JSON.parse(localStorage.getItem("nupur_bookings") || "[]");
      existing.push(bookingData);
      localStorage.setItem("nupur_bookings", JSON.stringify(existing));

      // Refresh slot list so this slot now appears disabled!
      await checkAndRenderSlotsForDate(date);

      showSuccessModal(bookingData);
    } catch (err) {
      console.error("Submission error:", err);
      // Fallback save in localStorage
      const existing = JSON.parse(localStorage.getItem("nupur_bookings") || "[]");
      existing.push(bookingData);
      localStorage.setItem("nupur_bookings", JSON.stringify(existing));
      showSuccessModal(bookingData);
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = `<span class="btn-icon">✨</span><span class="btn-text">Submit Booking Request (બુકિંગ વિનંતી મોકલો)</span>`;
    }
  });
}

function showSuccessModal(data) {
  const modal = document.getElementById("successModal");
  const receipt = document.getElementById("receiptBox");

  receipt.innerHTML = `
    <div class="receipt-row">
      <span class="receipt-label">Booking Reference:</span>
      <span class="receipt-val">#${data.bookingRef}</span>
    </div>
    <div class="receipt-row">
      <span class="receipt-label">Customer Name (નામ):</span>
      <span class="receipt-val">${data.customerName}</span>
    </div>
    <div class="receipt-row">
      <span class="receipt-label">Appointment Date (તારીખ):</span>
      <span class="receipt-val">${formatDateDisplay(data.bookingDate)}</span>
    </div>
    <div class="receipt-row">
      <span class="receipt-label">Time Slot (સમય):</span>
      <span class="receipt-val">${data.timeSlot}</span>
    </div>
    <div class="receipt-row">
      <span class="receipt-label">Services (સર્વિસ):</span>
      <span class="receipt-val">${data.serviceNames}</span>
    </div>
    <div class="receipt-row">
      <span class="receipt-label">Estimated Total (અંદાજિત રકમ):</span>
      <span class="receipt-val">₹${data.totalAmount}</span>
    </div>
  `;

  modal.classList.add("open");
}
