import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/lesson_resume.dart';

/// Where the learner left off, stored on the device under one JSON blob per
/// user — the same shape as `LocalProgressRepo`, and for the same reason: a
/// handful of lessons is small enough to rewrite wholesale on each save.
///
/// There is no Supabase counterpart on purpose. See [LessonResume] for why a
/// bookmark is device-local while progress is not.
class LessonResumeStore {
  const LessonResumeStore(this._prefs);

  final SharedPreferences _prefs;

  String _key(String userId) => 'resume.$userId';

  /// Every bookmark for a user, keyed by lesson id.
  ///
  /// Synchronous: shared_preferences is already in memory by the time any
  /// screen runs (it is loaded in `main()`), and the lesson player needs an
  /// answer before it can build its first frame — an async read would mean
  /// starting at card one and jumping.
  Map<String, LessonResume> readAll(String userId) {
    final String raw = _prefs.getString(_key(userId)) ?? '{}';
    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      // A corrupt bookmark is not worth failing a lesson over; losing it just
      // means starting the deck from the top.
      return <String, LessonResume>{};
    }
    return decoded.map(
      (String lessonId, dynamic value) => MapEntry<String, LessonResume>(
        lessonId,
        LessonResume.fromJson(value as Map<String, dynamic>),
      ),
    );
  }

  LessonResume? read({required String userId, required String lessonId}) =>
      readAll(userId)[lessonId];

  Future<void> writeAll({
    required String userId,
    required Map<String, LessonResume> bookmarks,
  }) {
    // An empty bookmark is indistinguishable from none, so it is dropped
    // rather than left to accumulate for every lesson ever opened.
    final Map<String, dynamic> encoded = <String, dynamic>{
      for (final MapEntry<String, LessonResume> entry in bookmarks.entries)
        if (!entry.value.isEmpty) entry.key: entry.value.toJson(),
    };
    if (encoded.isEmpty) return _prefs.remove(_key(userId));
    return _prefs.setString(_key(userId), jsonEncode(encoded));
  }

  Future<void> clear(String userId) => _prefs.remove(_key(userId));
}
