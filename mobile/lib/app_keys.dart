import 'package:flutter/material.dart';

/// Lets non-widget code (like the push notification listener) show an
/// in-app banner on whatever screen is currently open.
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Lets the alarm service show its ringing dialog on whatever screen is open.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
