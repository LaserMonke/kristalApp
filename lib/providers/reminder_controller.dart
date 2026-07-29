import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/local_reminder_service.dart';
import '../notifications/reminder_service.dart';
import 'repository_providers.dart';

/// Overridable seam so tests (and unsupported platforms) never touch the
/// notifications plugin.
final Provider<ReminderService> reminderServiceProvider =
    Provider<ReminderService>((Ref ref) => LocalReminderService());

/// The learner's reminder choice, persisted on-device.
///
/// Stored per DEVICE, not per user: a notification fires whether or not
/// anyone is signed in, so pretending it belongs to an account would be
/// dishonest. Off by default; enabling asks the OS for permission right then,
/// and a refusal leaves everything off.
class ReminderController extends AsyncNotifier<ReminderSettings> {
  static const String _prefsKey = 'reminders.settings';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);
  ReminderService get _service => ref.read(reminderServiceProvider);

  @override
  Future<ReminderSettings> build() async {
    final String? raw = _prefs.getString(_prefsKey);
    if (raw == null) return ReminderSettings.off;
    return ReminderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Turns the daily reminder on at [hour]:[minute]. Returns false (and stays
  /// off) if the OS permission was declined or the platform cannot schedule.
  Future<bool> enable({required int hour, required int minute}) async {
    final bool scheduled = await _service.scheduleDaily(
      hour: hour,
      minute: minute,
    );
    if (!scheduled) {
      await _save(
        (state.value ?? ReminderSettings.off).copyWith(
          enabled: false,
          hour: hour,
          minute: minute,
        ),
      );
      return false;
    }

    await _save(ReminderSettings(enabled: true, hour: hour, minute: minute));
    return true;
  }

  Future<void> disable() async {
    await _service.cancel();
    await _save(
      (state.value ?? ReminderSettings.off).copyWith(enabled: false),
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
