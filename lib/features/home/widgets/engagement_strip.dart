import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/level_badge_icons.dart';
import '../../../engagement/levels.dart';
import '../../../engagement/streak.dart';
import '../../../providers/engagement_providers.dart';

/// Streak, points and level at a glance, at the top of the Home tab.
///
/// Each stat is words + a number + an icon — never colour alone — and the
/// only "nudge" allowed is a plain statement of fact when a live streak has
/// no activity yet today (CLAUDE.md rule 9: encouragement, not guilt).
class EngagementStrip extends ConsumerWidget {
  const EngagementStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final StreakState streak =
        ref.watch(streakControllerProvider).value ?? StreakState.initial;
    final int points = ref.watch(totalPointsProvider);
    final Level level = ref.watch(levelProvider);

    final DateTime now = DateTime.now();
    final int days = streak.displayCurrent(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            _StatTile(
              icon: Icons.local_fire_department_outlined,
              value: '$days',
              label: 'day streak',
              semanticLabel: days == 0
                  ? 'No streak yet. Any lesson activity today starts one.'
                  : 'Streak: $days ${days == 1 ? 'day' : 'days'}.',
            ),
            const SizedBox(width: 10),
            _StatTile(
              icon: Icons.stars_outlined,
              value: '$points',
              label: points == 1 ? 'point' : 'points',
              semanticLabel: 'Points: $points.',
            ),
            const SizedBox(width: 10),
            _StatTile(
              icon: levelBadgeIcon(level.iconName),
              value: level.name,
              label: 'level ${level.rank} of ${levels.length}',
              semanticLabel:
                  'Level ${level.rank} of ${levels.length}: ${level.name}.',
            ),
          ],
        ),
        if (streak.needsActivity(now)) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'No activity yet today — one card keeps the streak going.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.semanticLabel,
  });

  final IconData icon;
  final String value;
  final String label;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Expanded(
      child: Semantics(
        label: semanticLabel,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
