import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/local/asset_lesson_repo.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/features/home/widgets/lesson_mark.dart';

/// The Home hero shows a mark for whatever lesson is next. The map is keyed by
/// lesson id, so it can rot in two directions: a new lesson with no mark, or a
/// mark for a lesson that has been removed. Both are caught here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Lesson> lessons;

  setUpAll(() async {
    lessons = await AssetLessonRepo().loadLessons();
  });

  test('every bundled lesson has its own mark', () {
    for (final Lesson lesson in lessons) {
      expect(
        markedLessonIds,
        contains(lesson.id),
        reason: '${lesson.id} would fall back to the default mark',
      );
    }
  });

  test('no mark points at a lesson that no longer exists', () {
    final Set<String> ids = <String>{
      for (final Lesson lesson in lessons) lesson.id,
    };
    for (final String marked in markedLessonIds) {
      expect(ids, contains(marked), reason: '$marked is not a lesson');
    }
  });

  test('every mark is exactly one of an icon or a glyph', () {
    for (final String id in markedLessonIds) {
      final LessonMark mark = markForLesson(id);
      expect(
        (mark.icon == null) != (mark.glyph == null),
        isTrue,
        reason: '$id must have an icon or a glyph, not both or neither',
      );
      expect(mark.label, isNotEmpty, reason: '$id needs a spoken label');
    }
  });

  test('the lessons about Greek letters are marked with Greek letters', () {
    expect(markForLesson('the-greeks').glyph, 'Δ');
    expect(markForLesson('volatility-is-not-constant').glyph, 'σ');
  });

  test('an unknown or absent lesson falls back to the app mark', () {
    expect(markForLesson(null).icon, kDefaultMark.icon);
    expect(markForLesson('no-such-lesson').icon, kDefaultMark.icon);
    // The fallback is what shows once the whole path is finished, so it has to
    // be a real mark rather than a blank.
    expect(kDefaultMark.icon, isNotNull);
    expect(kDefaultMark.label, isNotEmpty);
  });
}
