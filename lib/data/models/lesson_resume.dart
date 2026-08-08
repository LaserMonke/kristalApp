import 'quiz.dart';

/// The learner's bookmark in one lesson: the card that was on screen, and any
/// Q&A run they were part-way through.
///
/// Deliberately NOT part of `LessonProgress`. That record is what the learner
/// has ACHIEVED — cards read, best score, points — and it syncs to Postgres.
/// This is only where they happened to be standing when they walked away: it
/// changes on every swipe and every answer, and it is worth nothing once the
/// run it describes is finished. Keeping the two apart means a swipe costs no
/// network round trip, and a half-finished attempt never reaches a score or
/// the leaderboard.
///
/// Device-local, and honestly so: a learner who leaves a Q&A on their phone
/// and opens the same lesson on a tablet starts that run fresh. Their progress
/// still follows them; the bookmark does not.
class LessonResume {
  const LessonResume({required this.lessonId, this.cardIndex = 0, this.quiz});

  final String lessonId;

  /// Zero-based index of the card the learner was reading.
  ///
  /// Exact — it follows a swipe backwards as well as forwards, unlike
  /// `LessonProgress.cardsViewed`, which only ever counts the furthest card
  /// reached and so cannot say which one was actually on screen.
  final int cardIndex;

  /// The unfinished Q&A run, or null when there isn't one.
  final QuizResume? quiz;

  bool get isEmpty => cardIndex == 0 && quiz == null;

  LessonResume copyWith({
    int? cardIndex,
    QuizResume? quiz,
    bool clearQuiz = false,
  }) {
    return LessonResume(
      lessonId: lessonId,
      cardIndex: cardIndex ?? this.cardIndex,
      quiz: clearQuiz ? null : (quiz ?? this.quiz),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lesson_id': lessonId,
    'card_index': cardIndex,
    if (quiz != null) 'quiz': quiz!.toJson(),
  };

  factory LessonResume.fromJson(Map<String, dynamic> json) => LessonResume(
    lessonId: json['lesson_id'] as String,
    cardIndex: json['card_index'] as int? ?? 0,
    quiz: json['quiz'] == null
        ? null
        : QuizResume.fromJson(json['quiz'] as Map<String, dynamic>),
  );
}

/// Enough to drop a learner back into the middle of a Q&A run exactly as they
/// left it — same questions, same choice order, same answers already marked.
class QuizResume {
  const QuizResume({
    required this.seed,
    required this.questionIndex,
    required this.questionIds,
    required this.responses,
  });

  /// The run's shuffle seed. Stored rather than the resulting order, because
  /// [QuizSession.shuffled] is deterministic: replaying the seed puts every
  /// multiple choice back in the position the learner saw it in, which matters
  /// because an answer they already gave has to still sit next to the letter
  /// they picked.
  final int seed;

  /// The question the learner was on, zero-based.
  final int questionIndex;

  /// The questions this run was built from, in order.
  ///
  /// A fingerprint. An app update that adds, removes or reorders a lesson's
  /// questions — or a learner who changes their education level, which changes
  /// which questions are asked (see `Lesson.forProfile`) — invalidates the
  /// bookmark, rather than restoring answers against the wrong prompts.
  final List<String> questionIds;

  /// Question id → what the learner answered. Only answered questions appear.
  final Map<String, QuizResponse> responses;

  int get answered => responses.length;
  int get total => questionIds.length;

  /// Whether this bookmark still describes [questions].
  bool matches(List<QuizQuestion> questions) {
    if (questions.length != questionIds.length) return false;
    for (int i = 0; i < questions.length; i++) {
      if (questions[i].id != questionIds[i]) return false;
    }
    return true;
  }

  /// Rebuilds the session this bookmark came from.
  ///
  /// Verdicts are replayed from what was recorded, never re-graded: an answer
  /// marked wrong at the time stays wrong even if the question's tolerance or
  /// wording were edited in between. Call [matches] first.
  QuizSession restore(List<QuizQuestion> questions) {
    final QuizSession fresh = QuizSession.shuffled(
      questions: questions,
      seed: seed,
    );
    return QuizSession(
      questions: fresh.questions,
      verdicts: <String, bool>{
        for (final MapEntry<String, QuizResponse> entry in responses.entries)
          entry.key: entry.value.correct,
      },
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'seed': seed,
    'question_index': questionIndex,
    'question_ids': questionIds,
    'responses': responses.map(
      (String id, QuizResponse r) => MapEntry<String, dynamic>(id, r.toJson()),
    ),
  };

  factory QuizResume.fromJson(Map<String, dynamic> json) => QuizResume(
    seed: json['seed'] as int? ?? 0,
    questionIndex: json['question_index'] as int? ?? 0,
    questionIds: <String>[
      for (final dynamic id
          in json['question_ids'] as List<dynamic>? ?? const <dynamic>[])
        id as String,
    ],
    responses: <String, QuizResponse>{
      for (final MapEntry<String, dynamic> entry
          in (json['responses'] as Map<String, dynamic>? ??
                  const <String, dynamic>{})
              .entries)
        entry.key: QuizResponse.fromJson(entry.value as Map<String, dynamic>),
    },
  );
}

/// One answer the learner already gave, kept in the form the question asked
/// for so a restored screen can show it back to them: the choice they picked
/// still highlighted, or the number they typed still in the field.
class QuizResponse {
  const QuizResponse({required this.correct, this.choiceIndex, this.text});

  /// How it was marked at the time. Stored, not re-derived — see
  /// [QuizResume.restore].
  final bool correct;

  /// Index into the SHUFFLED choice list, for a multiple-choice question.
  /// Meaningful only alongside [QuizResume.seed], which is what fixes that
  /// order.
  final int? choiceIndex;

  /// What was typed, for a short-answer question.
  final String? text;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'correct': correct,
    if (choiceIndex != null) 'choice_index': choiceIndex,
    if (text != null) 'text': text,
  };

  factory QuizResponse.fromJson(Map<String, dynamic> json) => QuizResponse(
    correct: json['correct'] as bool? ?? false,
    choiceIndex: json['choice_index'] as int?,
    text: json['text'] as String?,
  );
}
