/// The seam between reminder SETTINGS (what the learner chose) and the
/// platform machinery that delivers notifications. The UI and controller talk
/// to this interface only, so tests can substitute a fake and the Windows/web
/// builds can report "not supported here" without touching plugin code.
library;

/// The three things worth being reminded about, each at its own time of day.
///
/// Three a day is the ceiling, not a target: every one is switched
/// independently, the wording invites and never chides, and turning any of
/// them off is one tap (CLAUDE.md rule 9). They are spread across the day
/// rather than stacked, so they read as three different invitations instead of
/// one app nagging three times.
enum ReminderKind {
  /// The original daily study reminder. Its copy comes from the learner's
  /// education level, so the defaults here are only a fallback.
  lesson(
    id: 1001,
    channelId: 'daily_reminder',
    channelName: 'Daily learning reminder',
    defaultHour: 18,
    defaultMinute: 0,
    defaultTitle: 'A few minutes of options?',
    defaultBody: 'Your next lesson is ready when you are.',
  ),

  /// Morning, because a puzzle is a good thing to arrive to.
  dailyGame(
    id: 1002,
    channelId: 'daily_game_reminder',
    channelName: 'Daily game',
    defaultHour: 9,
    defaultMinute: 0,
    defaultTitle: 'Today’s Stockle is up',
    defaultBody: 'A new NASDAQ-100 ticker, six tries. Play it or don’t.',
  ),

  /// Middle of the day, when a market would be open — though nothing here is
  /// a real market, and the copy says so rather than implying urgency.
  market(
    id: 1003,
    channelId: 'market_reminder',
    channelName: 'Practice market',
    defaultHour: 12,
    defaultMinute: 30,
    defaultTitle: 'Your practice portfolio',
    defaultBody:
        'Fake money, delayed prices. Have a look at how the positions sit.',
  );

  const ReminderKind({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.defaultHour,
    required this.defaultMinute,
    required this.defaultTitle,
    required this.defaultBody,
  });

  /// Stable notification id. Never reuse one: the OS keys a scheduled
  /// notification on it, so a changed id orphans whatever is already pending.
  final int id;
  final String channelId;
  final String channelName;
  final int defaultHour;
  final int defaultMinute;
  final String defaultTitle;
  final String defaultBody;
}

/// One reminder's state: on or off, and when.
class ReminderSlot {
  const ReminderSlot({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  /// Off, at this kind's default time — what an unset reminder looks like.
  factory ReminderSlot.offFor(ReminderKind kind) => ReminderSlot(
    enabled: false,
    hour: kind.defaultHour,
    minute: kind.defaultMinute,
  );

  final bool enabled;
  final int hour;
  final int minute;

  ReminderSlot copyWith({bool? enabled, int? hour, int? minute}) => ReminderSlot(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
  };

  static ReminderSlot fromJson(Map<String, dynamic>? json, ReminderKind kind) {
    if (json == null) return ReminderSlot.offFor(kind);
    return ReminderSlot(
      enabled: json['enabled'] as bool? ?? false,
      hour: (json['hour'] as int? ?? kind.defaultHour).clamp(0, 23),
      minute: (json['minute'] as int? ?? kind.defaultMinute).clamp(0, 59),
    );
  }
}

/// What the learner chose, for every reminder.
///
/// The first run on a phone turns all three on (see ReminderController) — but
/// the OS permission dialog is the real gate, a decline sticks, and each has
/// its own switch in Profile. Every slot's own default stays `false` so a
/// missing or corrupt stored value can never resurrect a reminder the learner
/// ended.
///
/// The lesson reminder keeps the flat `enabled` / `hour` / `minute` keys it has
/// always used, so an install that predates the other two reads back
/// unchanged. The newer kinds are absent from that older JSON and therefore
/// come back OFF: an app update must not start sending two extra notifications
/// a day to someone who never asked for them. They are one tap away in
/// Profile for anyone who wants them.
class ReminderSettings {
  const ReminderSettings({
    this.lesson = const ReminderSlot(enabled: false, hour: 18, minute: 0),
    this.dailyGame = const ReminderSlot(enabled: false, hour: 9, minute: 0),
    this.market = const ReminderSlot(enabled: false, hour: 12, minute: 30),
  });

  static const ReminderSettings off = ReminderSettings();

  final ReminderSlot lesson;
  final ReminderSlot dailyGame;
  final ReminderSlot market;

  ReminderSlot slot(ReminderKind kind) => switch (kind) {
    ReminderKind.lesson => lesson,
    ReminderKind.dailyGame => dailyGame,
    ReminderKind.market => market,
  };

  ReminderSettings withSlot(ReminderKind kind, ReminderSlot value) =>
      switch (kind) {
        ReminderKind.lesson => ReminderSettings(
          lesson: value,
          dailyGame: dailyGame,
          market: market,
        ),
        ReminderKind.dailyGame => ReminderSettings(
          lesson: lesson,
          dailyGame: value,
          market: market,
        ),
        ReminderKind.market => ReminderSettings(
          lesson: lesson,
          dailyGame: dailyGame,
          market: value,
        ),
      };

  /// True when at least one reminder is on.
  bool get anyEnabled => lesson.enabled || dailyGame.enabled || market.enabled;

  Map<String, dynamic> toJson() => <String, dynamic>{
    // Flat keys for the lesson reminder: the shape older installs wrote.
    'enabled': lesson.enabled,
    'hour': lesson.hour,
    'minute': lesson.minute,
    'dailyGame': dailyGame.toJson(),
    'market': market.toJson(),
  };

  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    return ReminderSettings(
      lesson: ReminderSlot(
        enabled: json['enabled'] as bool? ?? false,
        hour: (json['hour'] as int? ?? 18).clamp(0, 23),
        minute: (json['minute'] as int? ?? 0).clamp(0, 59),
      ),
      dailyGame: ReminderSlot.fromJson(
        json['dailyGame'] as Map<String, dynamic>?,
        ReminderKind.dailyGame,
      ),
      market: ReminderSlot.fromJson(
        json['market'] as Map<String, dynamic>?,
        ReminderKind.market,
      ),
    );
  }
}

abstract interface class ReminderService {
  /// Whether this platform can deliver scheduled reminders at all.
  bool get isSupported;

  /// Asks for OS notification permission (if needed) and schedules [kind] to
  /// repeat daily. Returns false — leaving nothing scheduled — when the
  /// learner declines permission or the platform refuses.
  ///
  /// [title] and [body] are supplied by the caller because the lesson
  /// reminder's wording is pitched to the learner's education level (see
  /// LearningProfile). The service delivers copy; it never writes it.
  Future<bool> scheduleDaily({
    required ReminderKind kind,
    required int hour,
    required int minute,
    required String title,
    required String body,
  });

  /// Cancels one reminder, leaving the others alone.
  Future<void> cancel(ReminderKind kind);
}
