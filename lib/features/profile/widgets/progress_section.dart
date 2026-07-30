import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/level_badge_icons.dart';
import '../../../engagement/levels.dart';
import '../../../engagement/streak.dart';
import '../../../providers/engagement_providers.dart';

/// Points, level, streak and the road to the certificate, on the Settings screen.
class ProgressSection extends ConsumerWidget {
  const ProgressSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int points = ref.watch(totalPointsProvider);
    final Level level = ref.watch(levelProvider);
    final StreakState streak =
        ref.watch(streakControllerProvider).value ?? StreakState.initial;
    final AsyncValue<CertificateStatus> certificate = ref.watch(
      certificateStatusProvider,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LevelCard(points: points, level: level),
        const SizedBox(height: 10),
        _StreakCard(streak: streak),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Completion certificate'),
            subtitle: Text(switch (certificate) {
              AsyncData<CertificateStatus>(:final CertificateStatus value)
                  when value.earned =>
                'Earned — open to view it',
              AsyncData<CertificateStatus>(:final CertificateStatus value) =>
                '${value.finishedLessons} of ${value.totalLessons} lessons '
                    'finished',
              _ => 'Finish every lesson and its Q&A',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.certificate),
          ),
        ),
      ],
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.points, required this.level});

  final int points;
  final Level level;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Level? next = nextLevelForPoints(points);
    final double progress = progressTowardNextLevel(points);

    final String toNext = next == null
        ? 'Top of the ladder.'
        : '${next.minPoints - points} points to ${next.name}.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          label:
              'Level ${level.rank} of ${levels.length}: ${level.name}. '
              '$points points. $toNext',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    height: 44,
                    width: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                      border: Border.all(color: theme.colorScheme.primary),
                    ),
                    child: Icon(
                      levelBadgeIcon(level.iconName),
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${level.name} · level ${level.rank} of '
                          '${levels.length}',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$points points',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.outline.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                toNext,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});

  final StreakState streak;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int days = streak.displayCurrent(DateTime.now());

    // The freeze explained as a fact, not a threat: what it is, whether it is
    // in hand, and how it comes back.
    final String freezeLine = streak.freezeAvailable
        ? 'Streak freeze ready — one missed day will not break the run.'
        : 'Freeze used. It returns after '
              '${freezeEarnBackDays - streak.daysTowardFreeze} more active '
              'days.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          label:
              '${days == 0 ? 'No current streak' : 'Streak: $days '
                  '${days == 1 ? 'day' : 'days'}'}. '
              'Longest: ${streak.longest}. $freezeLine',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.local_fire_department_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      days == 0
                          ? 'No streak right now'
                          : '$days-day streak',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Longest so far: ${streak.longest} '
                      '${streak.longest == 1 ? 'day' : 'days'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      freezeLine,
                      style: theme.textTheme.labelSmall?.copyWith(
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
