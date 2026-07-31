import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/disclaimer_text.dart';
import '../../core/widgets/settings_button.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../../data/models/app_user.dart';
import '../../data/models/learning_profile.dart';
import '../../providers/auth_controller.dart';
import '../../providers/lesson_providers.dart';
import '../leaderboard/leaderboard_screen.dart';

/// The Learn section — the lesson path and the Ranks board, as two tabs.
///
/// Ranks moved in here (Phase 9 restructure) so the fourth bottom-nav slot
/// could become the practice Market.
class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: const SettingsButton(),
          actions: const <Widget>[ThemeToggleButton(), SizedBox(width: 4)],
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Lessons'),
              Tab(text: 'Ranks'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[_LessonsView(), LeaderboardView()],
        ),
      ),
    );
  }
}

/// The learning path, driven entirely by lesson data.
class _LessonsView extends ConsumerWidget {
  const _LessonsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppUser? user = ref.watch(currentUserProvider);
    final LearningProfile profile = ref.watch(learningProfileProvider);
    final AsyncValue<List<LessonNode>> path = ref.watch(lessonPathProvider);

    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          // The greeting lives on Home; this tab leads with the curriculum.
          Text('Every lesson', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            user == null
                ? 'Start with what an option actually is.'
                : profile.pitch,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (user != null) ...<Widget>[
            const SizedBox(height: 6),
            // Personalisation is stated and changeable, never silent: a
            // learner should know why their path looks the way it does, and be
            // able to change it in one tap.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push(Routes.profile),
                icon: const Icon(Icons.tune, size: 16),
                label: Text('Change level (${user.educationLevel.label})'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const DisclaimerBanner(
            text: Disclaimers.noAdviceShort,
            icon: Icons.info_outline,
          ),
          const SizedBox(height: 20),
          Text('Your path', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          path.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
            error: (Object error, StackTrace _) => _PathError(
              onRetry: () => ref.invalidate(lessonsProvider),
            ),
            data: (List<LessonNode> nodes) => Column(
              children: <Widget>[
                for (final LessonNode node in nodes)
                  _LessonTile(node: node),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Each lesson ends with a short Q&A. More lessons are on the way.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.node});

  final LessonNode node;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool locked = !node.isUnlocked;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: locked
              ? () => _explainLock(context)
              : () => context.push(
                  node.needsQuiz
                      ? Routes.quizPath(node.lesson.id)
                      : Routes.lessonPath(node.lesson.id),
                ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _StatusBadge(node: node),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              node.lesson.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: locked
                                    ? theme.colorScheme.onSurfaceVariant
                                    : null,
                              ),
                            ),
                          ),
                          // Says which lessons build on the rest, so their
                          // position in the path is explained rather than
                          // arbitrary. It is a label, never a lock.
                          if (node.lesson.isAdvanced) ...<Widget>[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              child: Text(
                                'ADVANCED',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9,
                                  letterSpacing: 0.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        node.lesson.summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _StatusLine(node: node),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  locked
                      ? Icons.lock_outline
                      : node.needsQuiz
                      ? Icons.quiz_outlined
                      : Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _explainLock(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Finish the previous lesson and its Q&A to open this one.',
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.node});

  final LessonNode node;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool done = node.isFinished;

    return Container(
      height: 32,
      width: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? theme.pnl.correct.withValues(alpha: 0.16)
            : theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: done ? theme.pnl.correct : theme.colorScheme.outline,
        ),
      ),
      child: done
          ? Icon(Icons.check, size: 18, color: theme.pnl.correct)
          : Text('${node.lesson.order}', style: theme.textTheme.labelLarge),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.node});

  final LessonNode node;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (node.isFinished) {
      // Once there is a Q&A score, that is the more informative thing to show.
      final String label = node.progress.totalQuestions > 0
          ? 'Complete · Q&A ${node.progress.correctAnswers}'
                '/${node.progress.totalQuestions}'
          : 'Complete';
      return Text(label, style: style?.copyWith(color: theme.pnl.correct));
    }
    if (!node.isUnlocked) {
      return Text('Locked', style: style);
    }
    if (node.needsQuiz) {
      return Row(
        children: <Widget>[
          Icon(Icons.quiz_outlined, size: 13, color: theme.colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            'Cards read — Q&A next '
            '(${node.lesson.quizQuestionCount} questions)',
            style: style?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      );
    }
    if (node.isStarted) {
      return Row(
        children: <Widget>[
          SizedBox(
            width: 70,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: node.fractionRead,
                minHeight: 4,
                backgroundColor: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Card ${node.progress.cardsViewed} of ${node.lesson.cards.length}',
            style: style,
          ),
        ],
      );
    }
    return Text(
      '${node.lesson.cards.length} cards · about '
      '${node.lesson.estimatedMinutes} min',
      style: style,
    );
  }
}

class _PathError extends StatelessWidget {
  const _PathError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: <Widget>[
          Text('Lessons could not be loaded.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
