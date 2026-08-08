import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feedback/haptics.dart';
import '../../core/widgets/confetti_overlay.dart';
import '../../core/widgets/resume_note.dart';
import '../../core/router/app_router.dart';
import '../../data/models/lesson.dart';
import '../../data/models/lesson_resume.dart';
import '../../data/models/quiz.dart';
import '../../engagement/levels.dart';
import '../../engagement/streak.dart';
import '../../providers/engagement_providers.dart';
import '../../providers/lesson_providers.dart';
import '../../providers/lesson_resume_controller.dart';
import '../../providers/progress_controller.dart';
import 'widgets/quiz_question_view.dart';
import 'widgets/quiz_results_view.dart';

/// The graded Q&A that follows a lesson.
///
/// One question at a time, answered once, with the reasoning shown straight
/// away — feedback while the learner still remembers what they were thinking
/// is what makes it useful. Finishing the run is what unlocks the next lesson;
/// the score is reported honestly but never used to lock the learner out.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({required this.lessonId, super.key});

  final String lessonId;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  QuizSession? _session;
  int _index = 0;
  bool _finished = false;
  int _attempts = 1;

  /// Engagement outcome of the run just recorded, captured at save time so
  /// the results screen reports exactly what THIS run changed.
  int _pointsGained = 0;
  Level? _reachedLevel;
  int _streakDays = 0;

  /// True while the result is being written. Guards against a double-tap on
  /// "See results" recording the same run twice, which would count two
  /// attempts and make the results screen misreport how many goes it took.
  bool _saving = false;

  /// Bumped on a retake so every question widget is rebuilt from scratch.
  int _run = 0;

  /// The shuffle seed behind [_session]. Kept so the run can be written into
  /// the bookmark and replayed identically — see [QuizResume.seed].
  int _seed = 0;

  /// What the learner answered, question by question, in the form the question
  /// asked for. The session only records right/wrong; this also remembers the
  /// choice they tapped and the number they typed, which is what a restored
  /// screen has to show back to them.
  final Map<String, QuizResponse> _responses = <String, QuizResponse>{};

  /// True while the learner is still on the question they were dropped back
  /// onto, so the header can say why the Q&A did not start at question one.
  bool _resumed = false;

  /// The short-answer field, owned here rather than by the question widget so
  /// the pinned footer button can grade what is in it. On iOS the numeric
  /// keypad has no return key, so the submit control has to sit above the
  /// keyboard where it is always reachable.
  final TextEditingController _answer = TextEditingController();

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  /// Picks up an unfinished run, or starts a new one. Called once, when the
  /// lesson first becomes available.
  ///
  /// A Q&A left half-answered is worth resuming for the same reason a lesson
  /// is: the learner did the work. Answers are locked to a single attempt, so
  /// losing a run to a phone call would mean re-answering questions they had
  /// already thought through.
  void _ensureSession(Lesson lesson) {
    if (_session != null) return;

    final QuizResume? saved = ref
        .read(lessonResumeControllerProvider)[widget.lessonId]
        ?.quiz;

    // A bookmark whose questions no longer match the lesson — content updated,
    // or the learner changed their education level, which changes which
    // questions are asked — is dropped rather than replayed against the wrong
    // prompts.
    if (saved == null || !saved.matches(lesson.questions)) {
      _session = _newSession(lesson);
      return;
    }

    _seed = saved.seed;
    _session = saved.restore(lesson.questions);
    _responses.addAll(saved.responses);
    _index = saved.questionIndex.clamp(0, lesson.questions.length - 1);
    _resumed = _index > 0 || _responses.isNotEmpty;

    // A short answer already graded has to reappear in the field, which the
    // screen owns rather than the question widget.
    final String? typed = _responses[_session!.questions[_index].id]?.text;
    if (typed != null) _answer.text = typed;
  }

  /// A fresh run, with the multiple-choice answers reordered.
  ///
  /// Seeded from the clock so each attempt differs, and captured once per
  /// session so the order holds steady while the learner works through it —
  /// the question view and the results recap have to agree.
  QuizSession _newSession(Lesson lesson) {
    _seed = DateTime.now().microsecondsSinceEpoch;
    return QuizSession.shuffled(questions: lesson.questions, seed: _seed);
  }

  void _onAnswer(
    QuizQuestion question, {
    required bool correct,
    int? choiceIndex,
    String? text,
  }) {
    setState(() {
      _session = _session!.answer(question.id, correct: correct);
      _responses[question.id] = QuizResponse(
        correct: correct,
        choiceIndex: choiceIndex,
        text: text,
      );
      _resumed = false;
    });
    // A marked answer is worth feeling. Same tick either way — a heavier buzz
    // for a wrong answer would punish a learner for learning.
    ref.read(hapticsProvider).impact();
    _bookmark();
  }

  /// Grades whatever is in the field. No-op unless there is a number to grade,
  /// so an empty field is never submitted as a wrong answer.
  void _submitNumeric(NumericQuestion question) {
    if (_session!.verdictFor(question.id) != null) return;
    if (parseNumericAnswer(_answer.text) == null) return;

    FocusScope.of(context).unfocus();
    _onAnswer(
      question,
      correct: question.acceptsInput(_answer.text),
      text: _answer.text,
    );
  }

  /// Writes the run to the device so leaving the screen — or the app — does
  /// not throw away answers the learner has already committed to.
  void _bookmark() {
    ref
        .read(lessonResumeControllerProvider.notifier)
        .saveQuiz(
          lessonId: widget.lessonId,
          quiz: QuizResume(
            seed: _seed,
            questionIndex: _index,
            questionIds: <String>[
              for (final QuizQuestion q in _session!.questions) q.id,
            ],
            responses: Map<String, QuizResponse>.of(_responses),
          ),
        );
  }

  Future<void> _advance(Lesson lesson) async {
    if (_saving) return;
    if (_index < _session!.total - 1) {
      _answer.clear(); // The next question starts on an empty field.
      setState(() {
        _index++;
        _resumed = false;
      });
      _bookmark();
      return;
    }
    await _complete(lesson);
  }

  /// Writes the result through the ProgressRepo. This is the moment the next
  /// lesson opens (see `LessonNode.isFinished`).
  Future<void> _complete(Lesson lesson) async {
    _saving = true;

    // Points and level before the write, so the delta credited on the results
    // screen is what this run actually changed (a weaker retake changes
    // nothing — the best attempt is what counts).
    final int pointsBefore = ref.read(totalPointsProvider);
    final Level levelBefore = levelForPoints(pointsBefore);

    final QuizSession session = _session!;
    await ref
        .read(progressControllerProvider.notifier)
        .recordQuizResult(
          lessonId: lesson.id,
          correct: session.correct,
          total: session.total,
        );
    if (!mounted) return;

    final int pointsAfter = ref.read(totalPointsProvider);
    final Level levelAfter = levelForPoints(pointsAfter);
    final StreakState streak =
        ref.read(streakControllerProvider).value ?? StreakState.initial;

    setState(() {
      _finished = true;
      _attempts =
          ref
              .read(progressControllerProvider)
              .value?[lesson.id]
              ?.quizAttempts ??
          1;
      _pointsGained = pointsAfter - pointsBefore;
      _reachedLevel = levelAfter.rank > levelBefore.rank ? levelAfter : null;
      _streakDays = streak.displayCurrent(DateTime.now());
    });

    // A level-up is worth feeling as well as seeing — and it is the one place
    // in the app where the confetti fires, so the two belong together.
    if (_reachedLevel != null) ref.read(hapticsProvider).warn();
  }

  void _retry(Lesson lesson) {
    _answer.clear();
    _responses.clear();
    setState(() {
      _session = _newSession(lesson);
      _index = 0;
      _finished = false;
      _saving = false;
      _resumed = false;
      _run++;
    });
    // The previous run is scored and gone; the new one is bookmarked from its
    // first answer, not before, so abandoning it immediately leaves nothing to
    // resume.
    ref
        .read(lessonResumeControllerProvider.notifier)
        .clearQuiz(widget.lessonId);
  }

  void _reviewLesson() =>
      context.pushReplacement(Routes.lessonPath(widget.lessonId));

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.learn);
    }
  }

  /// The next lesson in the path — simply the one after this, whether or not
  /// it has been finished before.
  ///
  /// Deliberately not "the next UNFINISHED lesson": someone revisiting a Q&A
  /// on a course they have completed still expects the button to carry them
  /// onward, and skipping ahead to nothing is a worse answer than offering
  /// the lesson that literally comes next.
  ///
  /// Null only when this was the last lesson, or the path has not loaded — in
  /// which case the results screen falls back to the path rather than showing
  /// a button that goes nowhere.
  /// Watched, not read: this is reached from [build], and a `read` that has to
  /// flush the path there notifies its other listeners mid-build — which throws
  /// "setState() called during build" the moment anything else watches the
  /// path. Watching also means the button appears by itself once the path
  /// resolves, rather than staying absent until some other rebuild.
  LessonNode? get _nextLesson {
    final List<LessonNode>? path = ref.watch(lessonPathProvider).value;
    if (path == null) return null;

    final int here = path.indexWhere(
      (LessonNode n) => n.lesson.id == widget.lessonId,
    );
    if (here < 0 || here + 1 >= path.length) return null;
    return path[here + 1];
  }

  /// Straight into the next lesson, replacing this screen so the back gesture
  /// does not land the learner on a Q&A they have already finished.
  void _startNext(LessonNode next) =>
      context.pushReplacement(Routes.lessonPath(next.lesson.id));

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Lesson?> lesson = ref.watch(
      lessonProvider(widget.lessonId),
    );

    return Scaffold(
      body: SafeArea(
        child: lesson.when(
          loading: () => const Center(
            child: SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
          error: (Object error, StackTrace _) =>
              _QuizUnavailable(onClose: _close),
          data: (Lesson? data) {
            if (data == null || data.questions.isEmpty) {
              return _QuizUnavailable(onClose: _close);
            }
            _ensureSession(data);
            return _finished ? _buildResults(data) : _buildQuestion(data);
          },
        ),
      ),
    );
  }

  Widget _buildResults(Lesson lesson) {
    return Column(
      children: <Widget>[
        _QuizHeader(
          lessonTitle: lesson.title,
          label: 'Results',
          answered: _session!.total,
          total: _session!.total,
          onClose: _close,
        ),
        Expanded(
          // Confetti only for a level-up, which is rare by design — six
          // thresholds across the whole path. Firing it for every finished
          // Q&A would make it mean nothing.
          child: ConfettiOverlay(
            play: _reachedLevel != null,
            child: QuizResultsView(
              lessonTitle: lesson.title,
              session: _session!,
              attempts: _attempts,
              pointsGained: _pointsGained,
              reachedLevel: _reachedLevel,
              streakDays: _streakDays,
              onRetry: () => _retry(lesson),
              onReviewLesson: _reviewLesson,
              onDone: _close,
              nextLesson: _nextLesson,
              onStartNext: _startNext,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestion(Lesson lesson) {
    final QuizSession session = _session!;
    final QuizQuestion question = session.questions[_index];
    final bool? verdict = session.verdictFor(question.id);
    final bool isLast = _index == session.total - 1;

    return Column(
      children: <Widget>[
        _QuizHeader(
          lessonTitle: lesson.title,
          label: 'Question ${_index + 1} of ${session.total}',
          answered: _index,
          total: session.total,
          showResumeNote: _resumed,
          onClose: _close,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            // A numeric keypad cannot be dismissed with a return key, so
            // dragging the question is the way out of it.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: QuizQuestionView(
              // Identity per question AND per run: a retake starts clean.
              key: ValueKey<String>('$_run:${question.id}'),
              question: question,
              verdict: verdict,
              // Non-null only on a restored question: puts the tile the
              // learner tapped back under their answer, so a resumed screen
              // shows the same thing they were looking at when they left.
              selectedChoice: _responses[question.id]?.choiceIndex,
              answerController: _answer,
              onSubmitAnswer: question is NumericQuestion
                  ? () => _submitNumeric(question)
                  : () {},
              onAnswer: ({required bool correct, required int choiceIndex}) =>
                  _onAnswer(
                    question,
                    correct: correct,
                    choiceIndex: choiceIndex,
                  ),
            ),
          ),
        ),
        _Footer(
          question: question,
          verdict: verdict,
          isLast: isLast,
          answer: _answer,
          onSubmitNumeric: _submitNumeric,
          onAdvance: () => _advance(lesson),
        ),
      ],
    );
  }
}

/// The one action for the current question, pinned above the keyboard.
///
/// Being the only primary control is the point: an unanswered short-answer
/// question grades from here, an answered question moves on from here, and
/// neither can end up somewhere the keyboard covers.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.question,
    required this.verdict,
    required this.isLast,
    required this.answer,
    required this.onSubmitNumeric,
    required this.onAdvance,
  });

  final QuizQuestion question;
  final bool? verdict;
  final bool isLast;
  final TextEditingController answer;
  final void Function(NumericQuestion) onSubmitNumeric;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final Widget button = switch ((question, verdict)) {
      // Short answer, not yet graded: the button checks it, and stays disabled
      // until there is actually a number to check.
      (final NumericQuestion q, null) =>
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: answer,
          builder: (BuildContext context, TextEditingValue value, Widget? _) {
            final bool ready = parseNumericAnswer(value.text) != null;
            return FilledButton(
              onPressed: ready ? () => onSubmitNumeric(q) : null,
              child: const Text('Check answer'),
            );
          },
        ),
      // Anything else: advance, once the question has been answered.
      _ => FilledButton(
        onPressed: verdict == null ? null : onAdvance,
        child: Text(isLast ? 'See results' : 'Next question'),
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(width: double.infinity, child: button),
    );
  }
}

class _QuizHeader extends StatelessWidget {
  const _QuizHeader({
    required this.lessonTitle,
    required this.label,
    required this.answered,
    required this.total,
    required this.onClose,
    this.showResumeNote = false,
  });

  final String lessonTitle;
  final String label;

  /// Questions behind the learner, used for the segmented bar.
  final int answered;
  final int total;
  final VoidCallback onClose;

  /// Whether to explain that the run opened part-way through.
  final bool showResumeNote;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                tooltip: 'Leave the Q&A',
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(
                      'Q&A · $lessonTitle',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: label,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < total; i++)
                  Expanded(
                    child: Container(
                      height: 3,
                      margin: EdgeInsets.only(right: i == total - 1 ? 0 : 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: i <= answered
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ResumeNote(
            visible: showResumeNote,
            text: 'Picked up where you left off',
          ),
        ],
      ),
    );
  }
}

class _QuizUnavailable extends StatelessWidget {
  const _QuizUnavailable({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.help_outline, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'This lesson has no Q&A yet.',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onClose, child: const Text('Back')),
          ],
        ),
      ),
    );
  }
}
