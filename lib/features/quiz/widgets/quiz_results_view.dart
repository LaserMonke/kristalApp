import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/disclaimer_text.dart';
import '../../../data/models/quiz.dart';

/// The end of a Q&A run.
///
/// Completing the questions is what opens the next lesson, so this screen
/// never blocks. What it does instead is tell the learner plainly how they did
/// and, when the score was weak, point them back at the cards — a nudge rather
/// than a locked door (CLAUDE.md: no dark patterns).
class QuizResultsView extends StatelessWidget {
  const QuizResultsView({
    required this.lessonTitle,
    required this.session,
    required this.attempts,
    required this.onRetry,
    required this.onReviewLesson,
    required this.onDone,
    super.key,
  });

  final String lessonTitle;
  final QuizSession session;

  /// Including this one. Shown so a hard-won score is not passed off as a
  /// first-time result.
  final int attempts;

  final VoidCallback onRetry;
  final VoidCallback onReviewLesson;
  final VoidCallback onDone;

  /// Below this, the material has probably not landed yet.
  static const double _reviewThreshold = 0.6;

  bool get _shouldReview => session.score < _reviewThreshold;

  String get _headline {
    if (session.correct == session.total) return 'All correct';
    if (!_shouldReview) return 'Good work';
    return 'Worth another look';
  }

  String get _message {
    if (session.correct == session.total) {
      return 'You answered every question in "$lessonTitle" correctly. The '
          'next lesson is open.';
    }
    if (!_shouldReview) {
      return 'You have the main ideas from "$lessonTitle". The next lesson is '
          'open — the notes below cover what you missed.';
    }
    return 'A few of these did not land yet. The next lesson is open either '
        'way, but going back through the cards first will make it easier.';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        _ScoreDial(session: session),
        const SizedBox(height: 24),
        Text(
          _headline,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          _message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        if (attempts > 1) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            attempts == 2
                ? 'Second attempt at this Q&A.'
                : 'Attempt $attempts at this Q&A.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 28),
        Text('Question by question', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        for (int i = 0; i < session.questions.length; i++)
          _RecapRow(
            number: i + 1,
            question: session.questions[i],
            correct: session.verdictFor(session.questions[i].id) ?? false,
          ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onDone, child: const Text('Back to the path')),
        const SizedBox(height: 10),
        if (_shouldReview)
          OutlinedButton(
            onPressed: onReviewLesson,
            child: const Text('Read the lesson again'),
          )
        else
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Retake the Q&A'),
          ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _shouldReview ? onRetry : onReviewLesson,
          child: Text(
            _shouldReview ? 'Retake the Q&A' : 'Read the lesson again',
          ),
        ),
        const SizedBox(height: 20),
        const DisclaimerBanner(
          text: Disclaimers.noAdviceShort,
          icon: Icons.info_outline,
        ),
      ],
    );
  }
}

/// Score as a ring plus the raw count.
///
/// The number is spelled out next to the ring rather than left to the arc,
/// so the result never depends on reading a proportion off a shape.
class _ScoreDial extends StatelessWidget {
  const _ScoreDial({required this.session});

  final QuizSession session;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = session.score >= 0.6
        ? theme.pnl.correct
        : theme.colorScheme.primary;

    return Semantics(
      label:
          'Score: ${session.correct} out of ${session.total} correct.',
      excludeSemantics: true,
      child: Center(
        child: SizedBox(
          height: 132,
          width: 132,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              SizedBox.expand(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: session.score),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (BuildContext context, double value, Widget? _) =>
                      CircularProgressIndicator(
                        value: value,
                        strokeWidth: 9,
                        strokeCap: StrokeCap.round,
                        backgroundColor: theme.colorScheme.outline.withValues(
                          alpha: 0.4,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(tone),
                      ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${session.correct}/${session.total}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'correct',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecapRow extends StatelessWidget {
  const _RecapRow({
    required this.number,
    required this.question,
    required this.correct,
  });

  final int number;
  final QuizQuestion question;
  final bool correct;

  /// The right answer in one line, so the recap is useful without reopening
  /// the question.
  String get _answer => switch (question) {
    final MultipleChoiceQuestion q => q.correctChoice.text,
    final NumericQuestion q => q.formattedAnswer,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = correct ? theme.pnl.correct : theme.pnl.incorrect;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        label:
            'Question $number: ${correct ? 'correct' : 'not correct'}. '
            '${question.prompt} The answer was $_answer.',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                correct ? Icons.check_circle : Icons.cancel,
                size: 20,
                color: tone,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      question.prompt,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Answer: $_answer',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
