// Firebase Configuration for Nupur Beauty Parlour Online Bookings
// Replace with your Firebase Project Configuration from https://console.firebase.google.com/
const firebaseConfig = {
  apiKey: "YOUR_API_KEY",
  authDomain: "your-parlour-app.firebaseapp.com",
  projectId: "your-parlour-app",
  storageBucket: "your-parlour-app.appspot.com",
  messagingSenderId: "1234567890",
  appId: "1:1234567890:web:abcdef123456"
};

let db = null;

// Initialize Firebase if valid config exists
try {
  if (firebaseConfig.apiKey && firebaseConfig.apiKey !== "YOUR_API_KEY") {
    firebase.initializeApp(firebaseConfig);
    db = firebase.firestore();
    console.log("Firebase Firestore initialized successfully.");
  } else {
    console.warn("Firebase config not set yet. Direct WhatsApp mode is active.");
  }
} catch (e) {
  console.error("Error initializing Firebase:", e);
}
