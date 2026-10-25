// Required for FCM push notifications to work on Flutter web.
// This file must live at web/firebase-messaging-sw.js in your Flutter project
// (i.e. copy this whole `web` folder's contents into nutrifit_app/web/,
// don't replace the rest of that folder — just add this file).
//
// It uses the SAME Firebase config values as lib/firebase_options.dart's
// `web` block — if you ever re-run `flutterfire configure`, update the
// values below to match the new firebase_options.dart web section.

importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'REPLACE_WITH_YOUR_WEB_API_KEY',
  appId: 'REPLACE_WITH_YOUR_WEB_APP_ID',
  messagingSenderId: 'REPLACE_WITH_YOUR_MESSAGING_SENDER_ID',
  projectId: 'REPLACE_WITH_YOUR_PROJECT_ID',
});

const messaging = firebase.messaging();

// Handles notifications that arrive while the browser tab is closed/backgrounded.
messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification || {};
  if (title) {
    self.registration.showNotification(title, { body });
  }
});
