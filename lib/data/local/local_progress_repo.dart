import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../engagement/streak.dart';
import '../models/lesson_progress.dart';
import '../repositories/progress_repo.dart';

/// Progress stored in shared_preferences under one JSON blob per user.
///
/// Small enough to rewrite wholesale on each save (a handful of lessons); the
/// Supabase implementation in Phase 6 will write per-row instead.
class LocalProgressRepo implements ProgressRepo {
  LocalProgressRepo(this._prefs);

  final SharedPreferences _prefs;

  String _key(String userId) => 'progress.$userId';

  @override
  Future<Map<String, LessonProgress>> loadAll(String userId) async {
    final String raw = _prefs.getString(_key(userId)) ?? '{}';
    final Map<String, dynamic> decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (String lessonId, dynamic value) => MapEntry<String, LessonProgress>(
        lessonId,
        LessonProgress.fromJson(value as Map<String, dynamic>),
      ),
    );
  }

  @override
  Future<LessonProgress?> loadLesson({
    required String userId,
    required String lessonId,
  }) async {
    final Map<String, LessonProgress> all = await loadAll(userId);
    return all[lessonId];
  }

  @override
  Future<void> saveLesson({
    required String userId,
    required LessonProgress progress,
  }) async {
    final Map<String, LessonProgress> all = await loadAll(userId);
    all[progress.lessonId] = progress;

    final Map<String, dynamic> encoded = all.map(
      (String lessonId, LessonProgress value) =>
          MapEntry<String, dynamic>(lessonId, value.toJson()),
    );
    await _prefs.setString(_key(userId), jsonEncode(encoded));
  }

  /// Overwrites every lesson record for [userId] with [progress], dropping any
  /// lesson not present.
  ///
  /// Not part of [ProgressRepo]: it exists for the Supabase repository to mirror
  /// the server exactly. Warming the cache row-by-row would leave behind
  /// lessons the server no longer has (reset on another device), and those
  /// would reappear the next time the app read the cache offline. The streak is
  /// stored under its own key and is untouched.
  Future<void> replaceAll({
    required String userId,
    required Map<String, LessonProgress> progress,
  }) {
    final Map<String, dynamic> encoded = progress.map(
      (String lessonId, LessonProgress value) =>
          MapEntry<String, dynamic>(lessonId, value.toJson()),
    );
    return _prefs.setString(_key(userId), jsonEncode(encoded));
  }

  @override
  Future<int> totalPoints(String userId) async {
    final Map<String, LessonProgress> all = await loadAll(userId);
    return all.values.fold<int>(
      0,
      (int sum, LessonProgress p) => sum + p.pointsEarned,
    );
  }

  String _streakKey(String userId) => 'streak.$userId';

  @override
  Future<StreakState?> loadStreak(String userId) async {
    final String? raw = _prefs.getString(_streakKey(userId));
    if (raw == null) return null;
    return StreakState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> saveStreak({
    required String userId,
    required StreakState streak,
  }) => _prefs.setString(_streakKey(userId), jsonEncode(streak.toJson()));

  @override
  Future<void> clear(String userId) async {
    await _prefs.remove(_key(userId));
    await _prefs.remove(_streakKey(userId));
  }
}
