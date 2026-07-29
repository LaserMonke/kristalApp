import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/disclaimer_text.dart';
import '../../../core/widgets/level_badge_icons.dart';
import '../../../data/models/quiz.dart';
import '../../../engagement/levels.dart';

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
    required this.pointsGained,
    required this.streakDays,
    this.reachedLevel,
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

  /// Points this run added. Zero on a retake that did not beat the best
  /// score — reported as exactly that, not dressed up.
  final int pointsGained;

  /// The streak after this run counted toward today.
  final int streakDays;

  /// Set only when this run pushed the learner over a level threshold.
  final Level? reachedLevel;

  final VoidCallback onRetry;
  final VoidCallback onReviewLesson;
  final VoidCallback onDone;

  /// Below this, the material has probably not landed yet.
  static const double reviewThreshold = 0.6;

  bool get _shouldReview => session.score < reviewThreshold;

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
        const SizedBox(height: 20),
        _EarnedPanel(
          pointsGained: pointsGained,
          streakDays: streakDays,
          reachedLevel: reachedLevel,
        ),
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

/// What this run earned: points, the streak, and (rarely) a new level.
///
/// Honest by construction — a retake that did not improve the best score says
/// so instead of re-crediting old points, and a level-up appears only when a
/// threshold was actually crossed on this run.
class _EarnedPanel extends StatelessWidget {
  const _EarnedPanel({
    required this.pointsGained,
    required this.streakDays,
    required this.reachedLevel,
  });

  final int pointsGained;
  final int streakDays;
  final Level? reachedLevel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Level? level = reachedLevel;

    final String pointsLine = pointsGained > 0
        ? '+$pointsGained points'
        : 'No new points — your best score already counts';

    return Semantics(
      liveRegion: true,
      label: <String>[
        pointsLine,
        if (streakDays > 0)
          'Streak: $streakDays ${streakDays == 1 ? 'day' : 'days'}.',
        if (level != null) 'New level: ${level.name}.',
      ].join(' '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.stars_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    pointsLine,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: pointsGained > 0 ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
            if (streakDays > 0) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.local_fire_department_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$streakDays-day streak',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
            if (level != null) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    levelBadgeIcon(level.iconName),
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Level up: ${level.name}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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
    final Color tone = session.score >= QuizResultsView.reviewThreshold
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
