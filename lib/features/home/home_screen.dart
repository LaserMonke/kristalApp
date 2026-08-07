import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/disclaimer_text.dart';
import '../../core/widgets/settings_button.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../../games/stockle/stockle_engine.dart';
import '../../providers/engagement_providers.dart';
import '../../providers/lesson_providers.dart';
import '../../providers/stockle_providers.dart';
import 'widgets/home_hero.dart';

/// The landing tab: who you are, where you stand (streak, points, level),
/// what to do next, and how far the certificate is. Everything here is a
/// doorway — the lessons themselves live on the Learn tab.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<LessonNode>> path = ref.watch(lessonPathProvider);
    final AsyncValue<CertificateStatus> certificate = ref.watch(
      certificateStatusProvider,
    );

    return Scaffold(
      appBar: AppBar(
        leading: const SettingsButton(),
        actions: const <Widget>[
          // Stockle also has a card further down, but the hero and the next
          // lesson push that below the fold on a phone — a daily game nobody
          // scrolls to is a daily game nobody plays. This is always on screen,
          // named rather than left as a bare icon to guess at, and carries a
          // dot until today's puzzle has been played.
          _StockleButton(),
          ThemeToggleButton(),
          SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: <Widget>[
          const HomeHero(),
          // Gaps below the fold-critical part are tighter than the rest, so
          // "Up next" and the daily game both land on a phone screen instead
          // of the game starting just past the bottom edge.
          const SizedBox(height: 18),
          const _SectionHeader(
            icon: Icons.play_circle_outline,
            label: 'Up next',
          ),
          const SizedBox(height: 10),
          path.when(
            loading: () => const _CardLoading(),
            error: (Object error, StackTrace _) => const _CardNote(
              'Lessons could not be loaded. The Learn tab has a retry.',
            ),
            data: (List<LessonNode> nodes) => _NextLessonCard(nodes: nodes),
          ),
          const SizedBox(height: 18),
          const _SectionHeader(
            icon: Icons.grid_view_outlined,
            label: 'Daily game',
          ),
          const SizedBox(height: 10),
          const _StockleCard(),
          const SizedBox(height: 28),
          const _SectionHeader(
            icon: Icons.workspace_premium_outlined,
            label: 'Certificate',
          ),
          const SizedBox(height: 10),
          certificate.when(
            loading: () => const _CardLoading(),
            error: (Object error, StackTrace _) =>
                const _CardNote('Progress could not be loaded.'),
            data: (CertificateStatus status) =>
                _CertificateProgressCard(status: status),
          ),
          const SizedBox(height: 28),
          Divider(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 16),
          Text(
            Disclaimers.educationalOnly,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Entry point to Stockle, showing whether today's puzzle is still waiting.
///
/// States the streak but never nags about it: no countdown, no "don't lose
/// your streak" (CLAUDE.md rule 9 — streaks encourage, they do not guilt).
/// Always-visible way into Stockle, with a dot while today's puzzle is unplayed.
class _StockleButton extends ConsumerWidget {
  const _StockleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final StockleState? game = ref.watch(stockleProvider);
    final bool waiting = !(game?.isOver ?? false);

    return Tooltip(
      message: waiting ? 'Stockle — today’s puzzle is waiting' : 'Stockle',
      child: Badge(
        // The dot is a state, not a nag: it goes the moment the puzzle has
        // been played, win or lose, and never counts days missed
        // (CLAUDE.md rule 9).
        isLabelVisible: waiting,
        backgroundColor: theme.colorScheme.primary,
        // Sits over the label's top corner, so keep it off the text.
        offset: const Offset(-2, 2),
        child: TextButton.icon(
          onPressed: () => context.push(Routes.stockle),
          icon: const Icon(Icons.grid_view_outlined, size: 18),
          label: const Text('Stockle'),
        ),
      ),
    );
  }
}

class _StockleCard extends ConsumerWidget {
  const _StockleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final StockleState? game = ref.watch(stockleProvider);
    final StockleStats stats = ref.watch(stockleStatsProvider);

    final bool doneToday = game?.isOver ?? false;
    final String subtitle = doneToday
        ? (game!.isWon
              ? 'Solved in ${game.guessesUsed} — back tomorrow'
              : 'Today’s answer was ${game.answer.symbol}')
        : 'Guess today’s NASDAQ-100 ticker in $maxGuesses tries';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(Routes.stockle),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(
                doneToday ? Icons.check_circle_outline : Icons.grid_view,
                size: 28,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text('Stockle', style: theme.textTheme.titleMedium),
                        if (stats.streak > 0) ...<Widget>[
                          const SizedBox(width: 8),
                          Text(
                            '${stats.streak}-day streak',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// A consistent section heading — a muted icon beside the label — used for the
/// tab's stacked sections so they read as a set rather than loose text.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The single most useful action right now: resume the lesson in progress,
/// take its pending Q&A, or start the next unlocked lesson. When the path is
/// finished it points at the certificate instead.
class _NextLessonCard extends StatelessWidget {
  const _NextLessonCard({required this.nodes});

  final List<LessonNode> nodes;

  LessonNode? get _next {
    for (final LessonNode node in nodes) {
      if (!node.isFinished && node.isUnlocked) return node;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LessonNode? node = _next;

    if (node == null) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.check_circle, color: theme.pnl.correct),
          title: const Text('Every lesson is finished'),
          subtitle: const Text('Your completion certificate is ready to view.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.certificate),
        ),
      );
    }

    final String action = node.needsQuiz
        ? 'Start the Q&A'
        : node.isStarted
        ? 'Continue lesson'
        : 'Start lesson';
    final String status = node.needsQuiz
        ? 'Cards read — ${node.lesson.quizQuestionCount} questions to go'
        : node.isStarted
        ? 'Card ${node.progress.cardsViewed} of ${node.lesson.cards.length}'
        : '${node.lesson.cards.length} cards · about '
              '${node.lesson.estimatedMinutes} min';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(
          node.needsQuiz
              ? Routes.quizPath(node.lesson.id)
              : Routes.lessonPath(node.lesson.id),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Lesson ${node.lesson.order} · ${node.lesson.title}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                node.lesson.summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (node.isStarted && !node.needsQuiz) ...<Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: node.fractionRead,
                    minHeight: 4,
                    backgroundColor: theme.colorScheme.outline.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                status,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push(
                    node.needsQuiz
                        ? Routes.quizPath(node.lesson.id)
                        : Routes.lessonPath(node.lesson.id),
                  ),
                  child: Text(action),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How far the certificate is, as a fraction of lessons fully finished
/// (deck + Q&A). Words carry the number; the bar just illustrates it.
class _CertificateProgressCard extends StatelessWidget {
  const _CertificateProgressCard({required this.status});

  final CertificateStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double fraction = status.totalLessons == 0
        ? 0
        : status.finishedLessons / status.totalLessons;

    final String line = status.earned
        ? 'Earned — open to view it'
        : '${status.finishedLessons} of ${status.totalLessons} lessons '
              'finished';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(Routes.certificate),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Semantics(
            label: 'Certificate progress: $line.',
            excludeSemantics: true,
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.workspace_premium_outlined,
                  color: status.earned
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(line, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.outline.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardLoading extends StatelessWidget {
  const _CardLoading();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: SizedBox(
        height: 72,
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}

class _CardNote extends StatelessWidget {
  const _CardNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}
