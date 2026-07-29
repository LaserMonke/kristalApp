import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/local/asset_lesson_repo.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/engagement/levels.dart';
import 'package:optionsschool/engagement/points.dart';
import 'package:optionsschool/engagement/streak.dart';

/// The engagement rules are the honesty-sensitive part of Phase 5: points must
/// be monotonic, the streak must behave exactly as the UI describes it, and
/// the level ladder must be reachable from the shipped content.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DateTime day(int n) => DateTime(2026, 1, n, 14, 30); // Mid-afternoon local.

  group('points', () {
    test('rewards the deck, correct answers, and a perfect run', () {
      expect(
        lessonPoints(deckCompleted: true, correctAnswers: 0, totalQuestions: 0),
        deckCompletionPoints,
      );
      expect(
        lessonPoints(deckCompleted: true, correctAnswers: 3, totalQuestions: 4),
        deckCompletionPoints + 3 * pointsPerCorrectAnswer,
      );
      expect(
        lessonPoints(deckCompleted: true, correctAnswers: 4, totalQuestions: 4),
        deckCompletionPoints + 4 * pointsPerCorrectAnswer + perfectQuizBonus,
      );
    });

    test('no perfect bonus for an empty Q&A', () {
      expect(
        lessonPoints(
          deckCompleted: false,
          correctAnswers: 0,
          totalQuestions: 0,
        ),
        0,
      );
    });
  });

  group('levels', () {
    test('the ladder starts at zero and climbs strictly', () {
      expect(levels.first.minPoints, 0);
      for (int i = 1; i < levels.length; i++) {
        expect(
          levels[i].minPoints,
          greaterThan(levels[i - 1].minPoints),
          reason: '${levels[i].name} must cost more than ${levels[i - 1].name}',
        );
        expect(levels[i].rank, levels[i - 1].rank + 1);
      }
    });

    test('threshold boundaries land on the right level', () {
      expect(levelForPoints(0).name, 'Newcomer');
      expect(levelForPoints(39).name, 'Newcomer');
      expect(levelForPoints(40).name, 'Observer');
      expect(levelForPoints(9999).name, 'Graduate');
    });

    test('progress toward the next level is a clean fraction', () {
      expect(progressTowardNextLevel(0), 0);
      expect(progressTowardNextLevel(20), closeTo(0.5, 1e-9));
      expect(progressTowardNextLevel(levels.last.minPoints), 1);
      expect(nextLevelForPoints(levels.last.minPoints), isNull);
    });

    test('the top level is reachable from the shipped lessons', () async {
      final List<Lesson> lessons = await AssetLessonRepo().loadLessons();
      final int maxPoints = lessons.fold<int>(
        0,
        (int sum, Lesson lesson) =>
            sum +
            lessonPoints(
              deckCompleted: true,
              correctAnswers: lesson.questions.length,
              totalQuestions: lesson.questions.length,
            ),
      );
      expect(
        maxPoints,
        greaterThanOrEqualTo(levels.last.minPoints),
        reason:
            'Graduate must be earnable by finishing the shipped curriculum, '
            'or the ladder is a promise the app cannot keep',
      );
    });
  });

  group('streak', () {
    test('the first active day starts a one-day streak', () {
      final StreakResult r = StreakState.initial.register(day(1));
      expect(r.event, StreakEvent.started);
      expect(r.state.current, 1);
      expect(r.state.longest, 1);
    });

    test('more activity on the same day changes nothing', () {
      final StreakState s = StreakState.initial.register(day(1)).state;
      final StreakResult r = s.register(day(1).add(const Duration(hours: 5)));
      expect(r.event, StreakEvent.unchanged);
      expect(r.state.current, 1);
    });

    test('consecutive days extend the streak and track the longest', () {
      StreakState s = StreakState.initial.register(day(1)).state;
      s = s.register(day(2)).state;
      s = s.register(day(3)).state;
      expect(s.current, 3);
      expect(s.longest, 3);
    });

    test('one missed day is covered by the freeze, exactly once', () {
      StreakState s = StreakState.initial.register(day(1)).state;
      s = s.register(day(2)).state;

      // Day 3 missed; day 4 activity spends the freeze and the streak lives.
      final StreakResult saved = s.register(day(4));
      expect(saved.event, StreakEvent.freezeUsed);
      expect(saved.state.current, 3);
      expect(saved.state.freezeAvailable, isFalse);

      // Another one-day gap with no freeze left: reset.
      final StreakResult broken = saved.state.register(day(6));
      expect(broken.event, StreakEvent.reset);
      expect(broken.state.current, 1);
    });

    test('a gap of two or more missed days resets even with a freeze', () {
      final StreakState s = StreakState.initial.register(day(1)).state;
      final StreakResult r = s.register(day(4)); // Days 2 and 3 missed.
      expect(r.event, StreakEvent.reset);
      expect(r.state.current, 1);
      expect(r.state.freezeAvailable, isTrue, reason: 'nothing was spent');
    });

    test('the freeze is earned back after seven active days', () {
      StreakState s = StreakState.initial.register(day(1)).state;
      s = s.register(day(2)).state;
      s = s.register(day(4)).state; // Freeze spent covering day 3.
      expect(s.freezeAvailable, isFalse);
      expect(s.daysTowardFreeze, 1, reason: 'the comeback day counts');

      for (int d = 5; d <= 9; d++) {
        s = s.register(day(d)).state;
        expect(s.freezeAvailable, isFalse, reason: 'day $d is too soon');
      }
      s = s.register(day(10)).state; // Seventh active day since the spend.
      expect(s.freezeAvailable, isTrue);
      expect(s.daysTowardFreeze, 0);
    });

    test('longest survives a reset; current does not', () {
      StreakState s = StreakState.initial.register(day(1)).state;
      s = s.register(day(2)).state;
      s = s.register(day(3)).state;
      s = s.register(day(10)).state; // Long gap: reset.
      expect(s.current, 1);
      expect(s.longest, 3);
    });

    test('a clock set backwards cannot break an earned streak', () {
      final StreakState s = StreakState.initial.register(day(5)).state;
      final StreakResult r = s.register(day(3));
      expect(r.event, StreakEvent.unchanged);
      expect(r.state.current, 1);
    });

    test('display shows zero once the streak is already lost', () {
      StreakState s = StreakState.initial.register(day(1)).state;
      s = s.register(day(2)).state;

      expect(s.displayCurrent(day(2)), 2, reason: 'active today');
      expect(s.displayCurrent(day(3)), 2, reason: 'still saveable today');
      expect(s.displayCurrent(day(4)), 2,
          reason: 'one missed day, freeze in hand');
      expect(s.displayCurrent(day(5)), 0, reason: 'gone');

      expect(s.needsActivity(day(2)), isFalse);
      expect(s.needsActivity(day(3)), isTrue);
    });

    test('without a freeze, a one-day gap already displays as lost', () {
      StreakState s = StreakState.initial.register(day(1)).state;
      s = s.register(day(2)).state;
      s = s.register(day(4)).state; // Spends the freeze.
      expect(s.freezeAvailable, isFalse);
      expect(s.displayCurrent(day(6)), 0);
    });

    test('survives a JSON round trip', () {
      StreakState s = StreakState.initial.register(day(1)).state;
      s = s.register(day(2)).state;
      s = s.register(day(4)).state; // Freeze spent → non-default fields.

      final StreakState back = StreakState.fromJson(s.toJson());
      expect(back.current, s.current);
      expect(back.longest, s.longest);
      expect(back.lastActiveDay, s.lastActiveDay);
      expect(back.freezeAvailable, s.freezeAvailable);
      expect(back.daysTowardFreeze, s.daysTowardFreeze);
    });
  });
}
