import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/disclaimer_text.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../../data/models/app_user.dart';
import '../../providers/auth_controller.dart';
import '../../providers/engagement_providers.dart';
import '../../providers/lesson_providers.dart';
import 'widgets/engagement_strip.dart';

/// The landing tab: who you are, where you stand (streak, points, level),
/// what to do next, and how far the certificate is. Everything here is a
/// doorway — the lessons themselves live on the Learn tab.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppUser? user = ref.watch(currentUserProvider);
    final AsyncValue<List<LessonNode>> path = ref.watch(lessonPathProvider);
    final AsyncValue<CertificateStatus> certificate = ref.watch(
      certificateStatusProvider,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => context.push(Routes.profile),
        ),
        actions: const <Widget>[ThemeToggleButton(), SizedBox(width: 4)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          _Greeting(user: user),
          const SizedBox(height: 16),
          const EngagementStrip(),
          const SizedBox(height: 24),
          Text('Up next', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          path.when(
            loading: () => const _CardLoading(),
            error: (Object error, StackTrace _) => const _CardNote(
              'Lessons could not be loaded. The Learn tab has a retry.',
            ),
            data: (List<LessonNode> nodes) => _NextLessonCard(nodes: nodes),
          ),
          const SizedBox(height: 24),
          Text('Certificate', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          certificate.when(
            loading: () => const _CardLoading(),
            error: (Object error, StackTrace _) =>
                const _CardNote('Progress could not be loaded.'),
            data: (CertificateStatus status) =>
                _CertificateProgressCard(status: status),
          ),
          const SizedBox(height: 24),
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

/// Avatar + name, same visual language as the Profile identity card.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 26,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.16),
          child: Text(
            user?.initial ?? '?',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                user == null ? 'Welcome' : 'Welcome back, ${user!.username}',
                style: theme.textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
              if (user != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  'Lessons pitched for: ${user!.educationLevel.label}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
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
