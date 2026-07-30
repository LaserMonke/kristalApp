import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../engagement/streak.dart';
import '../local/local_progress_repo.dart';
import '../models/lesson_progress.dart';
import '../repositories/progress_repo.dart';
import 'supabase_error_messages.dart';
import 'supabase_tables.dart';

/// Learning progress synced to Postgres, with the on-device store kept as a
/// full offline fallback (Phase 6).
///
/// HOW IT BEHAVES OFFLINE — worth being precise about, because a learner who
/// finishes a lesson on the train must not lose it:
///   * Every write lands in the local cache FIRST, so progress survives a
///     failed request, a killed app, or airplane mode.
///   * The same write is then pushed to Postgres. If that fails for network
///     reasons the lesson id is queued and retried on the next successful
///     round trip. A rejection that is NOT a network problem (RLS, a broken
///     constraint) is surfaced, not silently queued — that would hide a bug.
///   * Reads prefer the server and fall back to the cache.
///
/// CONFLICTS ARE LAST-WRITE-WINS. Two devices used offline at once will keep
/// whichever flush arrives second. That is acceptable here because progress is
/// close to monotonic (cards viewed, best score, points) and nothing valuable
/// is destroyed by taking the later row; it is NOT a general sync engine.
///
/// POINTS ARE NOT SENT. `lesson_progress.points_earned` is a generated column
/// computed by Postgres from the same rules as lib/engagement/points.dart, so a
/// modified client cannot report its own score. We read it back; we never write
/// it.
class SupabaseProgressRepo implements ProgressRepo {
  // See the note in SupabaseProfileRepo: the language has no `this._field` form
  // for a private named parameter, so the lint's fix does not apply.
  SupabaseProgressRepo({
    required sb.SupabaseClient client,
    required LocalProgressRepo cache,
    required SharedPreferences prefs,
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // ignore: prefer_initializing_formals
       _cache = cache,
       // ignore: prefer_initializing_formals
       _prefs = prefs;

  final sb.SupabaseClient _client;

  /// The device-only repository from Part A, reused verbatim as the cache.
  /// Typed concretely because mirroring the server needs its [replaceAll].
  final LocalProgressRepo _cache;

  final SharedPreferences _prefs;

  // ---------------------------------------------------------------- reads

  @override
  Future<Map<String, LessonProgress>> loadAll(String userId) async {
    // Push anything stranded by an earlier outage before trusting the server,
    // otherwise a stale remote row would overwrite fresher local work.
    await _flushPending(userId);

    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(Db.lessonProgress)
          .select()
          .eq('user_id', userId);

      final Map<String, LessonProgress> remote =
          <String, LessonProgress>{
            for (final Map<String, dynamic> row in rows)
              row['lesson_id'] as String: _progressFromRow(row),
          };

      // Mirror the server exactly rather than merging row-by-row. Merging would
      // leave behind lessons the server no longer has — progress reset on
      // another device — and they would reappear on the next offline read.
      await _cache.replaceAll(userId: userId, progress: remote);
      return remote;
    } catch (error) {
      if (!isOfflineError(error)) rethrow;
      debugPrint('Progress read offline; using the on-device copy.');
      return _cache.loadAll(userId);
    }
  }

  @override
  Future<LessonProgress?> loadLesson({
    required String userId,
    required String lessonId,
  }) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from(Db.lessonProgress)
          .select()
          .eq('user_id', userId)
          .eq('lesson_id', lessonId)
          .maybeSingle();

      if (row == null) return null;
      final LessonProgress progress = _progressFromRow(row);
      await _cache.saveLesson(userId: userId, progress: progress);
      return progress;
    } catch (error) {
      if (!isOfflineError(error)) rethrow;
      return _cache.loadLesson(userId: userId, lessonId: lessonId);
    }
  }

  @override
  Future<int> totalPoints(String userId) async {
    final Map<String, LessonProgress> all = await loadAll(userId);
    return all.values.fold<int>(
      0,
      (int sum, LessonProgress p) => sum + p.pointsEarned,
    );
  }

  @override
  Future<StreakState?> loadStreak(String userId) async {
    await _flushPending(userId);

    try {
      final Map<String, dynamic>? row = await _client
          .from(Db.streaks)
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) return _cache.loadStreak(userId);

      final StreakState streak = _streakFromRow(row);
      await _cache.saveStreak(userId: userId, streak: streak);
      return streak;
    } catch (error) {
      if (!isOfflineError(error)) rethrow;
      return _cache.loadStreak(userId);
    }
  }

  // --------------------------------------------------------------- writes

  @override
  Future<void> saveLesson({
    required String userId,
    required LessonProgress progress,
  }) async {
    await _cache.saveLesson(userId: userId, progress: progress);

    try {
      await _client.from(Db.lessonProgress).upsert(
        _lessonPayload(userId, progress),
        onConflict: 'user_id,lesson_id',
      );
    } catch (error) {
      if (!isOfflineError(error)) rethrow;
      await _queueLesson(userId, progress.lessonId);
    }
  }

  @override
  Future<void> saveStreak({
    required String userId,
    required StreakState streak,
  }) async {
    await _cache.saveStreak(userId: userId, streak: streak);

    try {
      await _client
          .from(Db.streaks)
          .upsert(_streakPayload(userId, streak), onConflict: 'user_id');
    } catch (error) {
      if (!isOfflineError(error)) rethrow;
      await _setStreakPending(userId, pending: true);
    }
  }

  @override
  Future<void> clear(String userId) async {
    // Server FIRST, unlike every other write here. Wiping the device while
    // offline would look like it worked, then the next successful read would
    // pull the server's untouched rows straight back and silently undo the
    // reset. Failing out loud is the honest outcome.
    try {
      await _client.from(Db.lessonProgress).delete().eq('user_id', userId);
      await _client.from(Db.streaks).delete().eq('user_id', userId);
    } catch (error) {
      if (isOfflineError(error)) {
        throw const ProgressException(
          'Can’t reach the server, so nothing was reset. Try again when '
          'you’re back online.',
        );
      }
      rethrow;
    }

    await _cache.clear(userId);
    await _clearQueue(userId);
  }

  // ------------------------------------------------------- pending queue

  String _pendingLessonsKey(String userId) => 'sync.pending_lessons.$userId';
  String _pendingStreakKey(String userId) => 'sync.pending_streak.$userId';

  Future<void> _queueLesson(String userId, String lessonId) async {
    final Set<String> queued = <String>{
      ...?_prefs.getStringList(_pendingLessonsKey(userId)),
      lessonId,
    };
    await _prefs.setStringList(_pendingLessonsKey(userId), queued.toList());
  }

  Future<void> _setStreakPending(String userId, {required bool pending}) =>
      _prefs.setBool(_pendingStreakKey(userId), pending);

  Future<void> _clearQueue(String userId) async {
    await _prefs.remove(_pendingLessonsKey(userId));
    await _prefs.remove(_pendingStreakKey(userId));
  }

  /// Retries writes stranded by an outage. Silent on failure — it runs on the
  /// way to something else, and staying queued is the correct outcome.
  Future<void> _flushPending(String userId) async {
    final List<String> lessons =
        _prefs.getStringList(_pendingLessonsKey(userId)) ?? const <String>[];
    final bool streakPending = _prefs.getBool(_pendingStreakKey(userId)) ?? false;
    if (lessons.isEmpty && !streakPending) return;

    if (lessons.isNotEmpty) {
      final Map<String, LessonProgress> cached = await _cache.loadAll(userId);
      final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[
        for (final String lessonId in lessons)
          if (cached[lessonId] case final LessonProgress p)
            _lessonPayload(userId, p),
      ];

      if (payload.isNotEmpty) {
        try {
          await _client.from(Db.lessonProgress).upsert(
            payload,
            onConflict: 'user_id,lesson_id',
          );
          await _prefs.remove(_pendingLessonsKey(userId));
        } catch (error) {
          debugPrint('Progress still queued: ${error.runtimeType}');
          return;
        }
      } else {
        // Nothing left in the cache to send (progress was reset) — drop it.
        await _prefs.remove(_pendingLessonsKey(userId));
      }
    }

    if (streakPending) {
      final StreakState? streak = await _cache.loadStreak(userId);
      if (streak == null) {
        await _setStreakPending(userId, pending: false);
        return;
      }
      try {
        await _client
            .from(Db.streaks)
            .upsert(_streakPayload(userId, streak), onConflict: 'user_id');
        await _setStreakPending(userId, pending: false);
      } catch (error) {
        debugPrint('Streak still queued: ${error.runtimeType}');
      }
    }
  }

  // ------------------------------------------------------------- mapping

  /// Note the absence of `points_earned`: it is generated by Postgres.
  Map<String, dynamic> _lessonPayload(String userId, LessonProgress p) {
    return <String, dynamic>{
      'user_id': userId,
      'lesson_id': p.lessonId,
      'cards_viewed': p.cardsViewed,
      'lesson_completed': p.lessonCompleted,
      'quiz_completed': p.quizCompleted,
      'correct_answers': p.correctAnswers,
      'total_questions': p.totalQuestions,
      'quiz_attempts': p.quizAttempts,
      'last_opened_at': p.lastOpenedAt?.toUtc().toIso8601String(),
      'completed_at': p.completedAt?.toUtc().toIso8601String(),
    };
  }

  LessonProgress _progressFromRow(Map<String, dynamic> row) {
    return LessonProgress(
      lessonId: row['lesson_id'] as String,
      cardsViewed: row['cards_viewed'] as int? ?? 0,
      lessonCompleted: row['lesson_completed'] as bool? ?? false,
      quizCompleted: row['quiz_completed'] as bool? ?? false,
      correctAnswers: row['correct_answers'] as int? ?? 0,
      totalQuestions: row['total_questions'] as int? ?? 0,
      quizAttempts: row['quiz_attempts'] as int? ?? 0,
      pointsEarned: row['points_earned'] as int? ?? 0,
      lastOpenedAt: _localTimestamp(row['last_opened_at']),
      completedAt: _localTimestamp(row['completed_at']),
    );
  }

  Map<String, dynamic> _streakPayload(String userId, StreakState s) {
    return <String, dynamic>{
      'user_id': userId,
      'current_streak': s.current,
      'longest_streak': s.longest,
      // A DATE, not a timestamp: the streak is the learner's local "did I
      // learn today", so it must not shift with the timezone it is read in.
      'last_active_day': s.lastActiveDay == null
          ? null
          : _dateOnly(s.lastActiveDay!),
      'freeze_available': s.freezeAvailable,
      'days_toward_freeze': s.daysTowardFreeze,
    };
  }

  StreakState _streakFromRow(Map<String, dynamic> row) {
    final String? day = row['last_active_day'] as String?;
    return StreakState(
      current: row['current_streak'] as int? ?? 0,
      longest: row['longest_streak'] as int? ?? 0,
      // `DateTime.parse` on a bare date gives local midnight, which is exactly
      // what StreakState.dateOnly produces.
      lastActiveDay: day == null ? null : DateTime.tryParse(day),
      freezeAvailable: row['freeze_available'] as bool? ?? true,
      daysTowardFreeze: row['days_toward_freeze'] as int? ?? 0,
    );
  }

  static DateTime? _localTimestamp(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  static String _dateOnly(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
