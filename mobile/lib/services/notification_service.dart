import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'api_service.dart';

/// Must be a top-level (or static) function — this is how the OS wakes the app
/// to hand off a push notification that arrived while it was fully closed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nothing to do here beyond letting the OS show the notification itself
  // (which it does automatically for messages with a `notification` payload,
  // like the ones this backend sends). Kept as a named top-level function
  // because firebase_messaging requires one to be registered, even if empty.
}

class NotificationService {
  final ApiService api;
  NotificationService(this.api);

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _registeredFor;

  static const _channelId = 'nutrifit_reminders';
  static const _channelName = 'NutriFit Reminders';

  /// Call once after a successful sign-in. Sets up local notifications,
  /// requests permission, and registers this device for push notifications.
  Future<void> init(String token) async {
    if (_initialized) {
      // A different account signed in on this device: register this device for the new account.
      if (_registeredFor != token) await _registerDevice(token);
      return;
    }
    _initialized = true;

    tz_data.initializeTimeZones();
    try {
      final locationName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(locationName));
    } catch (_) {
      // Falls back to UTC if the device timezone can't be resolved — reminders
      // will still fire, just not necessarily at the exact intended local time.
    }

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      const channel = AndroidNotificationChannel(_channelId, _channelName, importance: Importance.high);
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    await _setupPush(token);
  }

  Future<void> _setupPush(String token) async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Foreground messages don't show a system notification automatically —
    // display one ourselves via the local notifications plugin.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;

      if (kIsWeb) return;
      _local.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(_channelId, _channelName, importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });

    await _registerDevice(token);
  }

  /// Registers this device's push token for the signed-in account (also called when another account signs in).
  Future<void> _registerDevice(String token) async {
    final messaging = FirebaseMessaging.instance;
    try {
      String? deviceToken;
      if (kIsWeb) {
        // Web push requires a VAPID key generated in Firebase Console
        // (Project Settings > Cloud Messaging > Web configuration > Generate key pair).
        // Without it, getToken() throws on web — caught below so sign-in still succeeds.
        deviceToken = await messaging.getToken(vapidKey: const String.fromEnvironment('FCM_VAPID_KEY'));
      } else {
        deviceToken = await messaging.getToken();
      }
      if (deviceToken != null) {
        await api.registerFcmToken(token, deviceToken);
        _registeredFor = token;
      }
    } catch (e) {
      // Non-fatal — push notifications just won't work until this succeeds,
      // but the rest of the app should never be blocked by it.
      // ignore: avoid_print
      print('FCM token registration skipped: $e');
    }
  }

  int _idFor(String reminderId) => reminderId.hashCode.abs() % 100000;

  /// Schedules (or re-schedules) a daily local notification for a reminder.
  /// Handles "6:00 AM" style times, and approximates "Every N hrs" patterns
  /// with fixed daily slots between 8 AM and 8 PM.
  Future<void> scheduleReminder({
    required String reminderId,
    required String timeLabel,
    required String title,
    required String subtitle,
  }) async {
    await cancelReminder(reminderId);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(_channelId, _channelName, importance: Importance.high, priority: Priority.high),
      iOS: DarwinNotificationDetails(),
    );

    final everyHoursMatch = RegExp(r'Every (\d+) hrs?', caseSensitive: false).firstMatch(timeLabel);
    if (everyHoursMatch != null) {
      final interval = int.tryParse(everyHoursMatch.group(1) ?? '2') ?? 2;
      var slot = 0;
      for (var hour = 8; hour <= 20; hour += interval) {
        await _local.zonedSchedule(
          _idFor('$reminderId-$slot'),
          title,
          subtitle,
          _nextInstanceOfTime(hour, 0),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
        slot++;
      }
      return;
    }

    final parsed = _parseTimeLabel(timeLabel);
    if (parsed == null) return; // unrecognized format — skip rather than crash
    await _local.zonedSchedule(
      _idFor(reminderId),
      title,
      subtitle,
      _nextInstanceOfTime(parsed.$1, parsed.$2),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelReminder(String reminderId) async {
    await _local.cancel(_idFor(reminderId));
    for (var slot = 0; slot < 12; slot++) {
      await _local.cancel(_idFor('$reminderId-$slot'));
    }
  }

  /// Parses strings like "6:00 AM" or "11:30 PM" into (hour24, minute).
  (int, int)? _parseTimeLabel(String label) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false).firstMatch(label.trim());
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)!.toUpperCase();
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    return (hour, minute);
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
