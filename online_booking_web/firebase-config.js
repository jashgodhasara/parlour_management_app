// Firebase Configuration for Nupur Beauty Parlour Online Bookings
// Replace with your Firebase Project Configuration from https://console.firebase.google.com/
// You can also change the projectId from the Flutter app Settings.

let savedConfig = null;
try {
  const localCfg = localStorage.getItem("nupur_firebase_web_config");
  if (localCfg) {
    savedConfig = JSON.parse(localCfg);
  }
} catch (e) {
  console.warn("Could not read local Firebase config:", e);
}

const firebaseConfig = savedConfig || {
  apiKey: "AIzaSyDummyKeyReplaceWithYourOwnApiKey",
  authDomain: "parlour-management-app.firebaseapp.com",
  projectId: "parlour-management-app",
  storageBucket: "parlour-management-app.appspot.com",
  messagingSenderId: "1234567890",
  appId: "1:1234567890:web:abcdef123456"
};

let db = null;
let isFirebaseActive = false;

// Initialize Firebase if valid config exists
try {
  if (
    typeof firebase !== "undefined" &&
    firebaseConfig.apiKey &&
    !firebaseConfig.apiKey.includes("ReplaceWithYourOwn") &&
    firebaseConfig.apiKey !== "YOUR_API_KEY"
  ) {
    if (!firebase.apps.length) {
      firebase.initializeApp(firebaseConfig);
    }
    db = firebase.firestore();
    isFirebaseActive = true;
    console.log("✅ Firebase Firestore initialized successfully for project:", firebaseConfig.projectId);
  } else {
    console.info("ℹ️ Running in Local/Demo fallback mode. Set valid Firebase config to sync over internet.");
  }
} catch (e) {
  console.error("Error initializing Firebase:", e);
}

// Helper to save web firebase config dynamically
function setFirebaseWebConfig(cfg) {
  if (cfg && cfg.projectId) {
    localStorage.setItem("nupur_firebase_web_config", JSON.stringify(cfg));
    window.location.reload();
  }
}
