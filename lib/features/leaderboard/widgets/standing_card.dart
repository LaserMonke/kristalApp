import 'package:flutter/material.dart';

import '../../../data/models/leaderboard.dart';

/// "Where am I?" — shown above the list so a learner outside the visible page
/// still knows their position.
class StandingCard extends StatelessWidget {
  const StandingCard({
    required this.standing,
    required this.period,
    this.bonusPoints = 0,
    super.key,
  });

  final LeaderboardStanding standing;
  final LeaderboardPeriod period;

  /// Extra points from the learner's practice-market performance, added to
  /// their total on this device (Phase 9). Zero when the portfolio is flat or
  /// down — market losses never subtract lesson points.
  final int bonusPoints;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = standing.points + bonusPoints;

    return Semantics(
      label:
          'Your standing: rank ${standing.rank} of ${standing.totalPlayers} '
          'on the board, $total points'
          '${bonusPoints > 0 ? ' including $bonusPoints from your practice portfolio' : ''}, '
          '${period.label}',
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'YOUR RANK',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        '#${standing.rank}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // "on the board", not "learners": the count includes any
                      // labelled bot entries (CLAUDE.md rule 7).
                      Text(
                        'of ${standing.totalPlayers} on the board',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    period.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('$total pts', style: theme.textTheme.titleLarge),
                  if (bonusPoints > 0)
                    Text(
                      '${standing.points} + $bonusPoints practice',
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
