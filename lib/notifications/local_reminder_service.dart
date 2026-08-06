import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_service.dart';

/// Daily reminders via flutter_local_notifications.
///
/// Up to three a day — lesson, daily game, practice market — each at its own
/// chosen local time and on its own Android channel, scheduled INEXACTLY: a
/// learning nudge does not justify exact-alarm permissions or battery cost.
/// The copy is a low-key invitation: no guilt, no urgency theatre, and no
/// profit language (CLAUDE.md rules 3 and 9).
class LocalReminderService implements ReminderService {
  LocalReminderService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

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
  Future<bool> scheduleDaily({
    required ReminderKind kind,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    if (!isSupported) return false;

    // Any platform failure — plugin missing, channel error, OS refusal — is
    // reported as "not scheduled" rather than crashing: a reminder is never
    // worth taking the app down for.
    try {
      return await _schedule(
        kind: kind,
        hour: hour,
        minute: minute,
        title: title,
        body: body,
      );
    } on Object {
      return false;
    }
  }

  Future<bool> _schedule({
    required ReminderKind kind,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    if (!await _requestPermission()) return false;

    // A channel per kind, so Android's own per-channel controls work: someone
    // who wants the lesson nudge but not the game can silence one from system
    // settings without losing the other, and without coming back here.
    await _plugin.zonedSchedule(
      id: kind.id,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          kind.channelId,
          kind.channelName,
          channelDescription: 'An opt-in daily reminder. Off in one tap.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeat at this wall-clock time every day.
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return true;
  }

  @override
  Future<void> cancel(ReminderKind kind) async {
    if (!isSupported) return;
    try {
      await _ensureInitialized();
      await _plugin.cancel(id: kind.id);
    } on Object {
      // Nothing scheduled or no plugin — either way there is nothing to
      // cancel, which is the state the caller wanted.
    }
  }
}
