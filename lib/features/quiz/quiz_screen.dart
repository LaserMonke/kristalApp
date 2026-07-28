import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/models/lesson.dart';
import '../../data/models/quiz.dart';
import '../../providers/lesson_providers.dart';
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

  /// Bumped on a retake so every question widget is rebuilt from scratch —
  /// otherwise a text field would still hold the previous run's answer.
  int _run = 0;

  void _ensureSession(Lesson lesson) {
    _session ??= QuizSession(questions: lesson.questions);
  }

  void _onAnswer(QuizQuestion question, {required bool correct}) {
    setState(() {
      _session = _session!.answer(question.id, correct: correct);
    });
  }

  Future<void> _advance(Lesson lesson) async {
    if (_index < _session!.total - 1) {
      setState(() => _index++);
      return;
    }
    await _complete(lesson);
  }

  /// Writes the result through the ProgressRepo. This is the moment the next
  /// lesson opens (see `LessonNode.isFinished`).
  Future<void> _complete(Lesson lesson) async {
    final QuizSession session = _session!;
    await ref
        .read(progressControllerProvider.notifier)
        .recordQuizResult(
          lessonId: lesson.id,
          correct: session.correct,
          total: session.total,
        );
    if (!mounted) return;

    setState(() {
      _finished = true;
      _attempts =
          ref.read(progressControllerProvider).value?[lesson.id]?.quizAttempts ??
          1;
    });
  }

  void _retry(Lesson lesson) {
    setState(() {
      _session = QuizSession(questions: lesson.questions);
      _index = 0;
      _finished = false;
      _run++;
    });
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
          error: (Object error, StackTrace _) => _QuizUnavailable(
            onClose: _close,
          ),
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
          child: QuizResultsView(
            lessonTitle: lesson.title,
            session: _session!,
            attempts: _attempts,
            onRetry: () => _retry(lesson),
            onReviewLesson: _reviewLesson,
            onDone: _close,
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
          onClose: _close,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: QuizQuestionView(
              // Identity per question AND per run: a retake starts clean.
              key: ValueKey<String>('$_run:${question.id}'),
              question: question,
              verdict: verdict,
              onAnswer: ({required bool correct}) =>
                  _onAnswer(question, correct: correct),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: verdict == null ? null : () => _advance(lesson),
              child: Text(isLast ? 'See results' : 'Next question'),
            ),
          ),
        ),
      ],
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
  });

  final String lessonTitle;
  final String label;

  /// Questions behind the learner, used for the segmented bar.
  final int answered;
  final int total;
  final VoidCallback onClose;

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
            Icon(
              Icons.help_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
