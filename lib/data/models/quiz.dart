/// Q&A content as DATA.
///
/// Same principle as the lesson cards (CLAUDE.md): questions live in the
/// bundled JSON next to the lesson they follow, and the engine renders and
/// grades whatever it is given. Adding a question is a content edit.
///
/// Two question types, because options understanding fails in two different
/// ways. A learner can mix up *who owes what* — a conceptual error, best
/// caught by multiple choice — or they can understand the contract and still
/// not be able to work out what it pays, which only a number they have to
/// compute themselves will expose.
library;

/// One graded question.
///
/// Sealed so the renderer's switch is exhaustive: a new question type won't
/// compile until it has both a visual treatment and a grading rule.
sealed class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.prompt,
    this.setup,
    this.teachingNote,
  });

  /// Stable within a lesson. Used to key answers, so reordering questions in
  /// the JSON never silently re-attributes a saved result.
  final String id;

  final String prompt;

  /// The scenario the question is about ("A call has strike $100…"), kept
  /// separate from the question itself so it can be styled as given facts.
  final String? setup;

  /// Shown after answering whether the learner was right or wrong — the point
  /// the question exists to make.
  final String? teachingNote;

  /// Spoken form for screen readers.
  String get semanticLabel;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final String type = json['type'] as String;
    return switch (type) {
      'choice' => MultipleChoiceQuestion.fromJson(json),
      'numeric' => NumericQuestion.fromJson(json),
      _ => throw FormatException('Unknown quiz question type "$type"'),
    };
  }
}

/// Pick one of several answers.
class MultipleChoiceQuestion extends QuizQuestion {
  const MultipleChoiceQuestion({
    required super.id,
    required super.prompt,
    required this.choices,
    super.setup,
    super.teachingNote,
  });

  final List<QuizChoice> choices;

  bool isCorrectChoice(int index) =>
      index >= 0 && index < choices.length && choices[index].isCorrect;

  /// The answer that should have been given, for the results recap.
  QuizChoice get correctChoice =>
      choices.firstWhere((QuizChoice c) => c.isCorrect);

  @override
  String get semanticLabel =>
      '${setup == null ? '' : '$setup '}$prompt Options: '
      '${choices.map((QuizChoice c) => c.text).join('; ')}.';

  factory MultipleChoiceQuestion.fromJson(Map<String, dynamic> json) =>
      MultipleChoiceQuestion(
        id: json['id'] as String,
        prompt: json['prompt'] as String,
        setup: json['setup'] as String?,
        teachingNote: json['teaching_note'] as String?,
        choices: <QuizChoice>[
          for (final dynamic c in json['choices'] as List<dynamic>)
            QuizChoice.fromJson(c as Map<String, dynamic>),
        ],
      );
}

/// One answer, with the reason it is right or wrong.
///
/// Every choice carries its own explanation, wrong ones included: a learner
/// who picked wrongly is the one who most needs to know why.
class QuizChoice {
  const QuizChoice({
    required this.text,
    required this.isCorrect,
    required this.explanation,
  });

  final String text;
  final bool isCorrect;
  final String explanation;

  factory QuizChoice.fromJson(Map<String, dynamic> json) => QuizChoice(
    text: json['text'] as String,
    isCorrect: json['correct'] as bool? ?? false,
    explanation: json['explanation'] as String,
  );
}

/// Short answer: work out a number and type it in.
///
/// Graded on an absolute tolerance rather than an exact match — the learner is
/// being asked whether they can apply the payoff arithmetic, not whether they
/// round the way we do.
class NumericQuestion extends QuizQuestion {
  const NumericQuestion({
    required super.id,
    required super.prompt,
    required this.answer,
    required this.explanation,
    super.setup,
    super.teachingNote,
    this.tolerance = 0.01,
    this.unitPrefix = '',
    this.unitSuffix = '',
    this.hint,
  });

  final double answer;

  /// Absolute tolerance, in the same units as [answer].
  final double tolerance;

  /// Currency symbol or similar, shown in the field and around the answer.
  final String unitPrefix;
  final String unitSuffix;

  /// How the number is arrived at. Shown after answering, either way.
  final String explanation;

  /// A nudge toward the right method, available before answering.
  final String? hint;

  bool accepts(double value) =>
      (value - answer).abs() <= tolerance + _floatingPointSlack;

  /// Grades raw learner input. Unparseable text is wrong, not an error.
  bool acceptsInput(String raw) {
    final double? value = parseNumericAnswer(raw);
    return value != null && accepts(value);
  }

  String get formattedAnswer => '$unitPrefix${formatQuizNumber(answer)}$unitSuffix';

  @override
  String get semanticLabel =>
      '${setup == null ? '' : '$setup '}$prompt Enter a number.';

  factory NumericQuestion.fromJson(Map<String, dynamic> json) => NumericQuestion(
    id: json['id'] as String,
    prompt: json['prompt'] as String,
    setup: json['setup'] as String?,
    teachingNote: json['teaching_note'] as String?,
    answer: (json['answer'] as num).toDouble(),
    tolerance: (json['tolerance'] as num? ?? 0.01).toDouble(),
    unitPrefix: json['unit_prefix'] as String? ?? '',
    unitSuffix: json['unit_suffix'] as String? ?? '',
    explanation: json['explanation'] as String,
    hint: json['hint'] as String?,
  );
}

/// Guards against a learner's exact answer failing on binary representation
/// (e.g. 0.1 + 0.2 landing just outside a 0.3 tolerance).
const double _floatingPointSlack = 1e-9;

/// Reads a number out of whatever the learner typed.
///
/// Tolerant of the ways people write money — `$105`, `105.00`, `1,050`, a
/// leading `+`, stray spaces — because none of those are the thing being
/// tested. Returns null when there is no number to grade.
double? parseNumericAnswer(String raw) {
  final String cleaned = raw
      .trim()
      .replaceAll(RegExp(r'[\s,$£€]'), '')
      .replaceAll('−', '-') // U+2212 minus, e.g. pasted from a payoff readout
      .replaceFirst(RegExp(r'^\+'), '');

  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// Trims the trailing `.0` so whole-dollar answers read as `$105`, not
/// `$105.0`, while keeping genuine decimals intact.
String formatQuizNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// The learner's run through one lesson's Q&A.
///
/// Immutable: answering returns a new session, which keeps the screen's state
/// transitions obvious and makes the scoring rules testable without a widget.
/// Nothing here decides whether the lesson is passed — it only counts.
class QuizSession {
  const QuizSession({
    required this.questions,
    this.verdicts = const <String, bool>{},
  });

  final List<QuizQuestion> questions;

  /// Question id → whether the learner got it right. Only the first answer to
  /// a question is recorded; the UI locks a question once it is answered, so a
  /// learner cannot tap through choices until one sticks.
  final Map<String, bool> verdicts;

  int get total => questions.length;
  int get answered => verdicts.length;
  int get correct => verdicts.values.where((bool v) => v).length;

  bool get isComplete => total > 0 && answered >= total;

  double get score => total == 0 ? 0 : correct / total;

  bool? verdictFor(String questionId) => verdicts[questionId];

  QuizSession answer(String questionId, {required bool correct}) {
    if (verdicts.containsKey(questionId)) return this;
    return QuizSession(
      questions: questions,
      verdicts: <String, bool>{...verdicts, questionId: correct},
    );
  }
}
