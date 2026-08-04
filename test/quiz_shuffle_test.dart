import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/local/asset_lesson_repo.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/data/models/quiz.dart';

/// A learner who notices the answer is always A stops reading the options and
/// starts pattern-matching. Two defences are tested here: the authored content
/// is not degenerate, and the engine reorders at run time regardless of what
/// was authored.
void main() {
  MultipleChoiceQuestion question({String id = 'q'}) => MultipleChoiceQuestion(
    id: id,
    prompt: 'p',
    choices: const <QuizChoice>[
      QuizChoice(text: 'right', isCorrect: true, explanation: 'e'),
      QuizChoice(text: 'wrong 1', isCorrect: false, explanation: 'e'),
      QuizChoice(text: 'wrong 2', isCorrect: false, explanation: 'e'),
      QuizChoice(text: 'wrong 3', isCorrect: false, explanation: 'e'),
    ],
  );

  int correctIndexOf(MultipleChoiceQuestion q) =>
      q.choices.indexWhere((QuizChoice c) => c.isCorrect);

  group('shuffling a question', () {
    test('keeps every choice, losing and inventing nothing', () {
      final MultipleChoiceQuestion original = question();
      final MultipleChoiceQuestion shuffled = original.shuffleChoices(
        math.Random(1),
      );

      expect(shuffled.choices, hasLength(original.choices.length));
      expect(
        shuffled.choices.map((QuizChoice c) => c.text).toSet(),
        original.choices.map((QuizChoice c) => c.text).toSet(),
      );
      expect(
        shuffled.choices.where((QuizChoice c) => c.isCorrect),
        hasLength(1),
      );
    });

    test('carries the question itself across unchanged', () {
      final MultipleChoiceQuestion original = MultipleChoiceQuestion(
        id: 'keep-me',
        prompt: 'p',
        setup: 's',
        teachingNote: 't',
        minDepth: 3,
        choices: question().choices,
      );
      final MultipleChoiceQuestion shuffled = original.shuffleChoices(
        math.Random(7),
      );

      expect(shuffled.id, 'keep-me');
      expect(shuffled.setup, 's');
      expect(shuffled.teachingNote, 't');
      expect(shuffled.minDepth, 3);
    });

    test('grading follows the new order', () {
      final MultipleChoiceQuestion shuffled = question().shuffleChoices(
        math.Random(3),
      );
      final int where = correctIndexOf(shuffled);

      expect(shuffled.isCorrectChoice(where), isTrue);
      for (int i = 0; i < shuffled.choices.length; i++) {
        if (i != where) expect(shuffled.isCorrectChoice(i), isFalse);
      }
      // And the recap still finds the right answer by flag, not position.
      expect(shuffled.correctChoice.text, 'right');
    });

    test('the answer does not sit in one place across seeds', () {
      final Set<int> seen = <int>{
        for (int seed = 0; seed < 40; seed++)
          correctIndexOf(question().shuffleChoices(math.Random(seed))),
      };
      expect(
        seen.length,
        greaterThan(1),
        reason: 'shuffling that always lands in the same slot is not shuffling',
      );
    });
  });

  group('a shuffled session', () {
    test('reorders multiple choice and leaves numeric questions alone', () {
      final QuizSession session = QuizSession.shuffled(
        questions: <QuizQuestion>[
          question(id: 'a'),
          const NumericQuestion(
            id: 'n',
            prompt: 'p',
            answer: 5,
            explanation: 'e',
          ),
        ],
        seed: 11,
      );

      expect(session.questions, hasLength(2));
      expect(session.questions[0], isA<MultipleChoiceQuestion>());
      final NumericQuestion numeric = session.questions[1] as NumericQuestion;
      expect(numeric.answer, 5, reason: 'numeric questions have no order');
    });

    test('the same seed gives the same order, so a session is stable', () {
      List<String> order(int seed) {
        final QuizSession s = QuizSession.shuffled(
          questions: <QuizQuestion>[question()],
          seed: seed,
        );
        return <String>[
          for (final QuizChoice c
              in (s.questions.single as MultipleChoiceQuestion).choices)
            c.text,
        ];
      }

      expect(order(99), order(99));
    });

    test('different seeds give different orders, so a retake is not memorised',
        () {
      List<String> order(int seed) {
        final QuizSession s = QuizSession.shuffled(
          questions: <QuizQuestion>[question()],
          seed: seed,
        );
        return <String>[
          for (final QuizChoice c
              in (s.questions.single as MultipleChoiceQuestion).choices)
            c.text,
        ];
      }

      final Set<String> distinct = <String>{
        for (int seed = 0; seed < 20; seed++) order(seed).join('|'),
      };
      expect(distinct.length, greaterThan(1));
    });

    test('answers are still recorded against the question id', () {
      final QuizSession session = QuizSession.shuffled(
        questions: <QuizQuestion>[question(id: 'a')],
        seed: 5,
      ).answer('a', correct: true);

      expect(session.verdictFor('a'), isTrue);
      expect(session.correct, 1);
    });
  });

  group('the authored content', () {
    late List<Lesson> lessons;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      lessons = await AssetLessonRepo().loadLessons();
    });

    test('no lesson keeps its correct answer in the same slot throughout', () {
      for (final Lesson lesson in lessons) {
        final List<int> positions = <int>[
          for (final QuizQuestion q in lesson.questions)
            if (q is MultipleChoiceQuestion) correctIndexOf(q),
        ];
        if (positions.length < 2) continue;
        expect(
          positions.toSet().length,
          greaterThan(1),
          reason:
              '${lesson.id} has every correct answer at position '
              '${positions.first}',
        );
      }
    });

    test('no single position dominates across the whole course', () {
      final List<int> all = <int>[
        for (final Lesson lesson in lessons)
          for (final QuizQuestion q in lesson.questions)
            if (q is MultipleChoiceQuestion) correctIndexOf(q),
      ];
      expect(all, isNotEmpty);

      final Map<int, int> counts = <int, int>{};
      for (final int i in all) {
        counts[i] = (counts[i] ?? 0) + 1;
      }
      final int worst = counts.values.reduce(math.max);
      expect(
        worst / all.length,
        lessThan(0.5),
        reason: 'authored positions are lopsided: $counts',
      );
    });
  });
}
