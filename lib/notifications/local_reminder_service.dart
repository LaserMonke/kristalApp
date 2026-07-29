import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_service.dart';

/// Daily reminder via flutter_local_notifications.
///
/// One notification a day at the learner's chosen local time, scheduled
/// INEXACTLY on Android — a learning nudge does not justify exact-alarm
/// permissions or battery cost. The copy is a low-key invitation to study:
/// no guilt, no urgency theatre, and no profit language (CLAUDE.md rules 3
/// and 9).
class LocalReminderService implements ReminderService {
  LocalReminderService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const int _dailyReminderId = 1001;

  @override
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    try {
      final TimezoneInfo zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object {
      // Unknown zone: tz.local stays at its default. The reminder still
      // fires daily, possibly offset — better than no reminder or a crash.
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is requested when the learner opts in, not at app start.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<bool> _requestPermission() async {
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final IOSFlutterLocalNotificationsPlugin? ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime at = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  @override
  Future<bool> scheduleDaily({required int hour, required int minute}) async {
    if (!isSupported) return false;

    await _ensureInitialized();
    if (!await _requestPermission()) return false;

    await _plugin.zonedSchedule(
      id: _dailyReminderId,
      title: 'A few minutes of options study?',
      body:
          'One lesson card at a time. Your pace — this reminder is off '
          'anytime in Profile.',
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          'Daily learning reminder',
          channelDescription:
              'The single opt-in daily reminder to keep learning.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeat at this wall-clock time every day.
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return true;
  }

  @override
  Future<void> cancel() async {
    if (!isSupported) return;
    await _ensureInitialized();
    await _plugin.cancel(id: _dailyReminderId);
  }
}
