import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/learning_profile.dart';
import '../notifications/local_reminder_service.dart';
import '../notifications/reminder_service.dart';
import 'lesson_providers.dart';
import 'repository_providers.dart';

/// Overridable seam so tests (and unsupported platforms) never touch the
/// notifications plugin.
final Provider<ReminderService> reminderServiceProvider =
    Provider<ReminderService>((Ref ref) => LocalReminderService());

/// The learner's reminder choice, persisted on-device.
///
/// Stored per DEVICE, not per user: a notification fires whether or not
/// anyone is signed in, so pretending it belongs to an account would be
/// dishonest.
///
/// ON BY DEFAULT on phones: the first run attempts to schedule all three
/// reminders, which surfaces the OS permission prompt — the system dialog is
/// the real consent gate on both iOS and Android 13+, so nothing can appear
/// without the learner agreeing to it. What keeps this on the right side of
/// CLAUDE.md rule 9: at most three a day and spread across it, each with its
/// own switch in Profile and its own Android channel, a declined prompt
/// treated as "no" and never re-asked at launch, and an explicit "off" never
/// overridden.
///
/// An EXISTING install is not opted into the two newer reminders. Its stored
/// settings predate them, they read back off, and they stay off until asked
/// for. Turning on two extra notifications a day through an app update is not
/// something an update gets to decide.
class ReminderController extends AsyncNotifier<ReminderSettings> {
  static const String _prefsKey = 'reminders.settings';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);
  ReminderService get _service => ref.read(reminderServiceProvider);

  /// Reminder wording follows the learner's education level: the register
  /// changes, never the pressure (CLAUDE.md rules 3 & 9).
  LearningProfile get _profile => ref.read(learningProfileProvider);

  @override
  Future<ReminderSettings> build() async {
    final String? raw = _prefs.getString(_prefsKey);
    if (raw != null) {
      // A stored choice — either way — is final until the learner changes it.
      return ReminderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    return _enableFirstRun();
  }

  /// The copy for [kind]. Only the lesson reminder is pitched to the
  /// learner's education level; the other two say the same thing to everyone,
  /// because a puzzle and a fake portfolio do not need a register.
  (String, String) _copy(ReminderKind kind) => switch (kind) {
    ReminderKind.lesson => (_profile.reminderTitle, _profile.reminderBody),
    _ => (kind.defaultTitle, kind.defaultBody),
  };

  /// First run only: try to turn every reminder on. The OS permission prompt
  /// appears on the first of them; declining leaves them all off, and the
  /// outcome is persisted so the learner is never prompted again at launch.
  Future<ReminderSettings> _enableFirstRun() async {
    if (!_service.isSupported) return ReminderSettings.off;

    ReminderSettings settings = ReminderSettings.off;
    for (final ReminderKind kind in ReminderKind.values) {
      final (String title, String body) = _copy(kind);
      final bool scheduled = await _service.scheduleDaily(
        kind: kind,
        hour: kind.defaultHour,
        minute: kind.defaultMinute,
        title: title,
        body: body,
      );
      settings = settings.withSlot(
        kind,
        ReminderSlot(
          enabled: scheduled,
          hour: kind.defaultHour,
          minute: kind.defaultMinute,
        ),
      );
      // A refusal is a refusal for all of them: the permission is app-wide,
      // so asking again per kind would just be the same dialog three times.
      if (!scheduled) break;
    }

    await _prefs.setString(_prefsKey, jsonEncode(settings.toJson()));
    return settings;
  }

  /// Turns [kind] on at [hour]:[minute]. Returns false (and leaves it off) if
  /// the OS permission was declined or the platform cannot schedule.
  Future<bool> enable(
    ReminderKind kind, {
    required int hour,
    required int minute,
  }) async {
    final (String title, String body) = _copy(kind);
    final bool scheduled = await _service.scheduleDaily(
      kind: kind,
      hour: hour,
      minute: minute,
      title: title,
      body: body,
    );

    final ReminderSettings current = state.value ?? ReminderSettings.off;
    await _save(
      current.withSlot(
        kind,
        ReminderSlot(enabled: scheduled, hour: hour, minute: minute),
      ),
    );
    return scheduled;
  }

  Future<void> disable(ReminderKind kind) async {
    await _service.cancel(kind);
    final ReminderSettings current = state.value ?? ReminderSettings.off;
    await _save(
      current.withSlot(kind, current.slot(kind).copyWith(enabled: false)),
    );
  }

  Future<void> _save(ReminderSettings settings) async {
    await _prefs.setString(_prefsKey, jsonEncode(settings.toJson()));
    state = AsyncValue<ReminderSettings>.data(settings);
  }
}

final AsyncNotifierProvider<ReminderController, ReminderSettings>
reminderControllerProvider =
    AsyncNotifierProvider<ReminderController, ReminderSettings>(
      ReminderController.new,
    );
