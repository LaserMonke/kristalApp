/// Daily learning streak (Phase 5). Pure Dart, no Flutter imports.
///
/// A day counts toward the streak when the learner does real learning work:
/// reads a new card, finishes a deck, or completes a Q&A. Merely opening the
/// app does not count.
///
/// Streak freeze (the "grace" in the build plan): the learner starts with one
/// freeze. Missing exactly ONE day consumes it automatically and the streak
/// survives; missing more than one day — or one day with no freeze in hand —
/// resets the streak. A spent freeze is earned back after
/// [freezeEarnBackDays] active days, counting the day the learner comes back.
///
/// Per CLAUDE.md rule 9 the streak encourages learning, not guilt: nothing in
/// the app is gated on it, a break costs nothing but the counter, and the
/// wording around it stays matter-of-fact.
library;

/// Active days needed to earn a spent freeze back.
const int freezeEarnBackDays = 7;

/// What a registered day of activity did to the streak. The UI uses this to
/// decide what (if anything) is worth mentioning.
enum StreakEvent {
  /// First active day ever (or first after a reset to zero state).
  started,

  /// Already counted today — nothing changed.
  unchanged,

  /// Consecutive day: streak grew by one.
  extended,

  /// One missed day was covered by the freeze; the streak survived and grew.
  freezeUsed,

  /// The gap was too long (or no freeze was available): back to day one.
  reset,
}

/// Immutable streak record. Dates are stored date-only in LOCAL time — a
/// streak is a human "did I learn today", not a UTC accounting question.
class StreakState {
  const StreakState({
    this.current = 0,
    this.longest = 0,
    this.lastActiveDay,
    this.freezeAvailable = true,
    this.daysTowardFreeze = 0,
  });

  static const StreakState initial = StreakState();

  /// Consecutive active days, ending on [lastActiveDay].
  final int current;
  final int longest;
  final DateTime? lastActiveDay;

  /// Whether one missed day would currently be forgiven.
  final bool freezeAvailable;

  /// Active days banked toward earning a spent freeze back.
  final int daysTowardFreeze;

  static DateTime dateOnly(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  /// Applies one day of learning activity at [now].
  StreakResult register(DateTime now) {
    final DateTime today = dateOnly(now);
    final DateTime? last = lastActiveDay;

    if (last == null) {
      return _advance(today, to: 1, event: StreakEvent.started);
    }

    final int gap = today.difference(last).inDays;
    if (gap <= 0) {
      // Same day again — or a clock set backwards, which we refuse to let
      // break a streak that was honestly earned.
      return StreakResult(this, StreakEvent.unchanged);
    }
    if (gap == 1) {
      return _advance(today, to: current + 1, event: StreakEvent.extended);
    }
    if (gap == 2 && freezeAvailable) {
      return _advance(
        today,
        to: current + 1,
        event: StreakEvent.freezeUsed,
        spendFreeze: true,
      );
    }
    return _advance(today, to: 1, event: StreakEvent.reset);
  }

  StreakResult _advance(
    DateTime today, {
    required int to,
    required StreakEvent event,
    bool spendFreeze = false,
  }) {
    bool freeze = spendFreeze ? false : freezeAvailable;
    int banked = spendFreeze ? 0 : daysTowardFreeze;

    // Every active day works toward earning a spent freeze back.
    if (!freeze) {
      banked += 1;
      if (banked >= freezeEarnBackDays) {
        freeze = true;
        banked = 0;
      }
    }

    return StreakResult(
      StreakState(
        current: to,
        longest: to > longest ? to : longest,
        lastActiveDay: today,
        freezeAvailable: freeze,
        daysTowardFreeze: banked,
      ),
      event,
    );
  }

  /// The streak as it should be DISPLAYED at [asOf], without writing anything:
  /// 0 once the streak is already lost, even though [current] still holds the
  /// old run until the next activity is registered. A one-day gap with a
  /// freeze in hand still shows as alive — the freeze will cover it.
  int displayCurrent(DateTime asOf) {
    final DateTime? last = lastActiveDay;
    if (last == null) return 0;
    final int gap = dateOnly(asOf).difference(last).inDays;
    if (gap <= 1) return current;
    if (gap == 2 && freezeAvailable) return current;
    return 0;
  }

  /// True when the streak is alive but today has no activity yet — the state
  /// in which a reminder or nudge is honest rather than manufactured.
  bool needsActivity(DateTime asOf) =>
      displayCurrent(asOf) > 0 && dateOnly(asOf) != lastActiveDay;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'current': current,
    'longest': longest,
    'last_active_day': lastActiveDay?.toIso8601String(),
    'freeze_available': freezeAvailable,
    'days_toward_freeze': daysTowardFreeze,
  };

  factory StreakState.fromJson(Map<String, dynamic> json) {
    return StreakState(
      current: json['current'] as int? ?? 0,
      longest: json['longest'] as int? ?? 0,
      lastActiveDay: DateTime.tryParse(
        json['last_active_day'] as String? ?? '',
      ),
      freezeAvailable: json['freeze_available'] as bool? ?? true,
      daysTowardFreeze: json['days_toward_freeze'] as int? ?? 0,
    );
  }
}

class StreakResult {
  const StreakResult(this.state, this.event);

  final StreakState state;
  final StreakEvent event;
}
