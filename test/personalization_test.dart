import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/models/education_level.dart';
import 'package:optionsschool/data/models/learning_profile.dart';
import 'package:optionsschool/data/models/lesson.dart';
import 'package:optionsschool/data/models/quiz.dart';

/// Personalisation changes what a learner meets first and what they are asked
/// by default. The two rules that keep it defensible — nothing is hidden, and
/// risk copy is never softened — are the ones worth testing hardest.
void main() {
  QuizQuestion question(String id, {int minDepth = 1}) =>
      MultipleChoiceQuestion(
        id: id,
        prompt: 'p',
        minDepth: minDepth,
        choices: const <QuizChoice>[
          QuizChoice(text: 'a', isCorrect: true, explanation: 'e'),
          QuizChoice(text: 'b', isCorrect: false, explanation: 'e'),
        ],
      );

  Lesson lesson({
    required String id,
    required int order,
    int? advancedOrder,
    bool advanced = false,
    List<QuizQuestion> questions = const <QuizQuestion>[],
    List<LessonCard> cards = const <LessonCard>[
      SummaryCard(heading: 'h', takeaways: <String>[]),
    ],
  }) => Lesson(
    id: id,
    order: order,
    advancedOrder: advancedOrder,
    isAdvanced: advanced,
    title: id,
    summary: 's',
    cards: cards,
    questions: questions,
  );

  group('profiles', () {
    test('every level resolves to a profile', () {
      for (final EducationLevel level in EducationLevel.values) {
        final LearningProfile p = LearningProfile.forLevel(level);
        expect(p.level, level);
        expect(p.pitch, isNotEmpty);
        expect(p.reminderTitle, isNotEmpty);
        expect(p.reminderBody, isNotEmpty);
      }
    });

    test('only the more experienced levels reorder the path', () {
      expect(
        LearningProfile.forLevel(EducationLevel.highSchool).usesAdvancedOrder,
        isFalse,
      );
      expect(
        LearningProfile.forLevel(
          EducationLevel.undergraduate,
        ).usesAdvancedOrder,
        isFalse,
      );
      expect(
        LearningProfile.forLevel(EducationLevel.postgraduate).usesAdvancedOrder,
        isTrue,
      );
      expect(
        LearningProfile.forLevel(EducationLevel.earlyCareer).usesAdvancedOrder,
        isTrue,
      );
    });

    test('only high school skips the stretch questions by default', () {
      for (final EducationLevel level in EducationLevel.values) {
        final bool asks = LearningProfile.forLevel(level).asksStretchQuestions;
        expect(asks, level != EducationLevel.highSchool, reason: level.name);
      }
    });

    test('no reminder copy promises profit or leans on guilt', () {
      const List<String> banned = <String>[
        'make money',
        'profit',
        'get rich',
        'guaranteed',
        'returns',
        'earn money',
        'don\'t miss',
        'falling behind',
        'losing your',
      ];
      for (final EducationLevel level in EducationLevel.values) {
        final LearningProfile p = LearningProfile.forLevel(level);
        final String copy = '${p.reminderTitle} ${p.reminderBody}'
            .toLowerCase();
        for (final String phrase in banned) {
          expect(copy.contains(phrase), isFalse, reason: '$level: "$phrase"');
        }
      }
    });

    test('every reminder says how to turn it off', () {
      for (final EducationLevel level in EducationLevel.values) {
        final LearningProfile p = LearningProfile.forLevel(level);
        expect(p.reminderBody.toLowerCase(), contains('settings'));
      }
    });
  });

  group('path order', () {
    final List<Lesson> lessons = <Lesson>[
      lesson(id: 'strategies', order: 6, advancedOrder: 8),
      lesson(id: 'vol', order: 8, advancedOrder: 6, advanced: true),
      lesson(id: 'basics', order: 1, advancedOrder: 1),
    ];

    List<String> ordered(EducationLevel level) {
      final LearningProfile p = LearningProfile.forLevel(level);
      final List<Lesson> copy = List<Lesson>.of(lessons)
        ..sort((Lesson a, Lesson b) => a.orderFor(p).compareTo(b.orderFor(p)));
      return <String>[for (final Lesson l in copy) l.id];
    }

    test('a beginner walks the authored order', () {
      expect(ordered(EducationLevel.highSchool), <String>[
        'basics',
        'strategies',
        'vol',
      ]);
    });

    test('an experienced learner meets the advanced material sooner', () {
      expect(ordered(EducationLevel.postgraduate), <String>[
        'basics',
        'vol',
        'strategies',
      ]);
    });

    test('a lesson with no advanced order keeps its place', () {
      final Lesson l = lesson(id: 'x', order: 3);
      final LearningProfile p = LearningProfile.forLevel(
        EducationLevel.postgraduate,
      );
      expect(l.orderFor(p), 3);
    });

    test('everyone still gets every lesson — the path only reorders', () {
      expect(
        ordered(EducationLevel.highSchool).toSet(),
        ordered(EducationLevel.postgraduate).toSet(),
      );
      expect(ordered(EducationLevel.highSchool).length, lessons.length);
    });
  });

  group('question difficulty', () {
    final Lesson mixed = lesson(
      id: 'l',
      order: 1,
      questions: <QuizQuestion>[
        question('a'),
        question('b', minDepth: 2),
        question('c'),
      ],
    );

    test('a beginner is not asked the stretch question', () {
      final Lesson forHs = mixed.forProfile(
        LearningProfile.forLevel(EducationLevel.highSchool),
      );
      expect(forHs.quizQuestionCount, 2);
      expect(
        forHs.questions.any((QuizQuestion q) => q.minDepth > 1),
        isFalse,
      );
    });

    test('everyone else gets the full set', () {
      for (final EducationLevel level in EducationLevel.values) {
        if (level == EducationLevel.highSchool) continue;
        expect(
          mixed.forProfile(LearningProfile.forLevel(level)).quizQuestionCount,
          3,
          reason: level.name,
        );
      }
    });

    test('a lesson of nothing but stretch questions keeps its Q&A', () {
      // Dropping every question would silently change what finishing this
      // lesson means, which is worse than asking a hard question.
      final Lesson allStretch = lesson(
        id: 'l',
        order: 1,
        questions: <QuizQuestion>[
          question('a', minDepth: 2),
          question('b', minDepth: 2),
        ],
      );
      final Lesson forHs = allStretch.forProfile(
        LearningProfile.forLevel(EducationLevel.highSchool),
      );
      expect(forHs.hasQuiz, isTrue);
      expect(forHs.quizQuestionCount, 2);
    });

    test('a card outside the band is dropped from the main flow', () {
      final Lesson banded = lesson(
        id: 'l',
        order: 1,
        cards: const <LessonCard>[
          SummaryCard(heading: 'everyone', takeaways: <String>[]),
          SummaryCard(
            heading: 'scaffold',
            takeaways: <String>[],
            maxDepth: 2,
          ),
          SummaryCard(heading: 'deep', takeaways: <String>[], minDepth: 3),
        ],
        questions: <QuizQuestion>[question('a')],
      );

      final List<String> beginner = <String>[
        for (final LessonCard c
            in banded
                .forProfile(LearningProfile.forLevel(EducationLevel.highSchool))
                .cards)
          (c as SummaryCard).heading,
      ];
      final List<String> expert = <String>[
        for (final LessonCard c
            in banded
                .forProfile(
                  LearningProfile.forLevel(EducationLevel.postgraduate),
                )
                .cards)
          (c as SummaryCard).heading,
      ];

      expect(beginner, <String>['everyone', 'scaffold']);
      expect(expert, <String>['everyone', 'deep']);
    });

    test('a deeper card is still reachable, never deleted', () {
      final Lesson banded = lesson(
        id: 'l',
        order: 1,
        cards: const <LessonCard>[
          SummaryCard(heading: 'everyone', takeaways: <String>[]),
          SummaryCard(heading: 'deep', takeaways: <String>[], minDepth: 3),
        ],
      );
      final LearningProfile hs = LearningProfile.forLevel(
        EducationLevel.highSchool,
      );
      expect(banded.deeperCards(hs), hasLength(1));
      expect((banded.deeperCards(hs).single as SummaryCard).heading, 'deep');
      // And nothing is deeper than an expert's own level.
      expect(
        banded.deeperCards(
          LearningProfile.forLevel(EducationLevel.postgraduate),
        ),
        isEmpty,
      );
    });

    test('a band that would empty a lesson falls back to showing it all', () {
      final Lesson impossible = lesson(
        id: 'l',
        order: 1,
        cards: const <LessonCard>[
          SummaryCard(heading: 'deep', takeaways: <String>[], minDepth: 4),
        ],
      );
      expect(
        impossible
            .forProfile(LearningProfile.forLevel(EducationLevel.highSchool))
            .cards,
        hasLength(1),
      );
    });

    test('personalising twice is stable', () {
      final LearningProfile p = LearningProfile.forLevel(
        EducationLevel.highSchool,
      );
      expect(mixed.forProfile(p).forProfile(p).quizQuestionCount, 2);
    });
  });
}
