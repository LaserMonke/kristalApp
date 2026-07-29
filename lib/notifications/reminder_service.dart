/// The seam between reminder SETTINGS (what the learner chose) and the
/// platform machinery that delivers notifications. The UI and controller talk
/// to this interface only, so tests can substitute a fake and the Windows/web
/// builds can report "not supported here" without touching plugin code.
library;

/// What the learner chose. Off by default — reminders are strictly opt-in
/// (CLAUDE.md rule 9), and enabling asks the OS for permission at that moment.
class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.hour = 18,
    this.minute = 0,
  });

  static const ReminderSettings off = ReminderSettings();

  final bool enabled;

  /// Local wall-clock time of the single daily reminder.
  final int hour;
  final int minute;

  ReminderSettings copyWith({bool? enabled, int? hour, int? minute}) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
  };

  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    return ReminderSettings(
      enabled: json['enabled'] as bool? ?? false,
      hour: (json['hour'] as int? ?? 18).clamp(0, 23),
      minute: (json['minute'] as int? ?? 0).clamp(0, 59),
    );
  }
}

abstract interface class ReminderService {
  /// Whether this platform can deliver scheduled reminders at all.
  bool get isSupported;

  /// Asks for OS notification permission (if needed) and schedules the one
  /// daily reminder. Returns false — leaving nothing scheduled — when the
  /// learner declines permission or the platform refuses.
  Future<bool> scheduleDaily({required int hour, required int minute});

  /// Cancels the daily reminder.
  Future<void> cancel();
}
