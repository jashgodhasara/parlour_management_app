// Services Catalog
const PARLOUR_SERVICES = [
  {
    category: "✨ Festive Special Packages",
    items: [
      { id: "pkg_glow", name: "Festive Golden Glow Package (Facial + D-Tan + Wax + Threading)", price: 1499, duration: "90 min" },
      { id: "pkg_bridal", name: "Festive Party Makeup & Hair Styling Combo", price: 1999, duration: "120 min" },
      { id: "pkg_hair_spa", name: "Hair Spa + Herbal Cleanup + Manicure Combo", price: 999, duration: "75 min" }
    ]
  },
  {
    category: "💇‍♀️ Hair Services & Treatments",
    items: [
      { id: "hair_cut", name: "Hair Cut & Styling", price: 250, duration: "30 min" },
      { id: "hair_spa", name: "L'Oreal Hair Spa", price: 650, duration: "45 min" },
      { id: "hair_color", name: "Hair Color / Root Touch-up", price: 500, duration: "60 min" },
      { id: "hair_straightening", name: "Hair Smoothening / Keratin Treatment", price: 2499, duration: "180 min" }
    ]
  },
  {
    category: "✨ Skin Care & Facials",
    items: [
      { id: "facial_gold", name: "Gold / Diamond Glow Facial", price: 850, duration: "50 min" },
      { id: "facial_clean", name: "Fruit / Herbal Cleanup", price: 400, duration: "35 min" },
      { id: "dtan_pack", name: "D-Tan Face & Neck Glow Pack", price: 300, duration: "25 min" },
      { id: "hydra_facial", name: "Hydra Deep Glow Facial", price: 1200, duration: "60 min" }
    ]
  },
  {
    category: "💅 Waxing & Threading",
    items: [
      { id: "threading_eyebrow", name: "Eyebrow & Upper Lip Threading", price: 70, duration: "15 min" },
      { id: "wax_full_hand_leg", name: "Full Hands & Half Legs Honey Waxing", price: 450, duration: "40 min" },
      { id: "wax_rica", name: "Rica Brazilian / White Chocolate Waxing", price: 750, duration: "45 min" }
    ]
  },
  {
    category: "🌿 Makeup & Mehendi",
    items: [
      { id: "party_makeup", name: "HD Festive Party Makeup", price: 1200, duration: "60 min" },
      { id: "mehendi_hands", name: "Festive Designer Mehendi (Both Hands)", price: 500, duration: "45 min" }
    ]
  }
];

// Parlour contact for direct WhatsApp message
const PARLOUR_WHATSAPP_NUMBER = "919427451121";

let selectedServices = [];
let lastBookingData = null;

// Initialize form
document.addEventListener("DOMContentLoaded", () => {
  renderServices();
  setupDateLimits();
  setupFormListener();
});

// Set minimum date to today
function setupDateLimits() {
  const dateInput = document.getElementById("bookingDate");
  const today = new Date().toISOString().split("T")[0];
  dateInput.min = today;
  dateInput.value = today;
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

// Form submit handler
function setupFormListener() {
  const form = document.getElementById("bookingForm");
  const submitBtn = document.getElementById("submitBtn");

  form.addEventListener("submit", async (e) => {
    e.preventDefault();

    const name = document.getElementById("custName").value.trim();
    const phone = document.getElementById("custPhone").value.trim();
    const date = document.getElementById("bookingDate").value;
    const time = document.getElementById("timeSlot").value;
    const notes = document.getElementById("notes").value.trim();

    if (!name || !phone || !date || !time) {
      alert("Please fill in all required fields.");
      return;
    }

    if (selectedServices.length === 0) {
      alert("Please select at least one service.");
      return;
    }

    const totalAmount = selectedServices.reduce((sum, s) => sum + s.price, 0);
    const serviceNames = selectedServices.map(s => s.name).join(", ");
    const bookingRef = "NP-" + Math.floor(100000 + Math.random() * 900000);

    const bookingData = {
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
    submitBtn.innerHTML = `<span>⏳</span> Submitting your booking request...`;

    try {
      if (db) {
        await db.collection("online_bookings").add(bookingData);
        console.log("Booking written to Firestore successfully.");
      } else {
        const existing = JSON.parse(localStorage.getItem("nupur_bookings") || "[]");
        existing.push(bookingData);
        localStorage.setItem("nupur_bookings", JSON.stringify(existing));
      }

      showSuccessModal(bookingData);
    } catch (err) {
      console.error("Submission error:", err);
      showSuccessModal(bookingData);
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = `<span class="btn-icon">✨</span><span class="btn-text">Submit Booking Request</span>`;
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
      <span class="receipt-label">Customer Name:</span>
      <span class="receipt-val">${data.customerName}</span>
    </div>
    <div class="receipt-row">
      <span class="receipt-label">Appointment Date:</span>
      <span class="receipt-val">${data.bookingDate}</span>
    </div>
    <div class="receipt-row">
      <span class="receipt-label">Time Slot:</span>
      <span class="receipt-val">${data.timeSlot}</span>
    </div>
    <div class="receipt-row">
      <span class="receipt-label">Selected Services:</span>
      <span class="receipt-val">${data.serviceNames}</span>
    </div>
    <div class="receipt-row">
      <span class="receipt-label">Estimated Total:</span>
      <span class="receipt-val">₹${data.totalAmount}</span>
    </div>
  `;

  modal.classList.add("open");

  // WhatsApp Button
  const btnWhatsApp = document.getElementById("btnSendWhatsApp");
  btnWhatsApp.onclick = () => {
    const msg = encodeURIComponent(
      `✨ *Nupur Beauty Parlour - Online Booking Request*\n\n` +
      `👤 *Name:* ${data.customerName}\n` +
      `📞 *Mobile:* ${data.customerPhone}\n` +
      `📅 *Date:* ${data.bookingDate}\n` +
      `⏰ *Time:* ${data.timeSlot}\n` +
      `💅 *Services:* ${data.serviceNames}\n` +
      `💰 *Estimated Total:* ₹${data.totalAmount}\n` +
      (data.notes ? `📝 *Note:* ${data.notes}\n` : ``) +
      `\nPlease confirm my appointment booking. Thank you!`
    );
    window.open(`https://wa.me/${PARLOUR_WHATSAPP_NUMBER}?text=${msg}`, "_blank");
  };
}
