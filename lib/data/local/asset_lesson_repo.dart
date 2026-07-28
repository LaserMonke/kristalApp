import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/lesson.dart';
import '../repositories/lesson_repo.dart';

/// Lessons parsed from the JSON bundled with the app.
///
/// Decoded once and cached: the content is static for the lifetime of the
/// process, and re-parsing on every card swipe would be wasteful.
class AssetLessonRepo implements LessonRepo {
  AssetLessonRepo({AssetBundle? bundle, this.assetPath = defaultAssetPath})
    : _bundle = bundle ?? rootBundle;

  static const String defaultAssetPath = 'assets/lessons/lessons.json';

  final AssetBundle _bundle;
  final String assetPath;

  Future<List<Lesson>>? _cached;

  @override
  Future<List<Lesson>> loadLessons() => _cached ??= _parse();

  @override
  Future<Lesson?> loadLesson(String lessonId) async {
    final List<Lesson> lessons = await loadLessons();
    for (final Lesson lesson in lessons) {
      if (lesson.id == lessonId) return lesson;
    }
    return null;
  }

  Future<List<Lesson>> _parse() async {
    final String raw = await _bundle.loadString(assetPath);
    final Map<String, dynamic> decoded = jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> rawLessons = decoded['lessons'] as List<dynamic>;

    final List<Lesson> lessons = <Lesson>[
      for (final dynamic lesson in rawLessons)
        Lesson.fromJson(lesson as Map<String, dynamic>),
    ]..sort((Lesson a, Lesson b) => a.order.compareTo(b.order));

    return List<Lesson>.unmodifiable(lessons);
  }
}
