import 'package:flutter/material.dart';

import '../../../data/models/leaderboard.dart';

/// One learner (or one labelled bot) on the board.
///
/// Accessibility: the bot label and the "you" marker are not colour-only —
/// each carries text, and the whole row has a single Semantics label so a
/// screen reader reads "4th, ana, 140 points, you" rather than four fragments.
class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({required this.entry, required this.isMe, super.key});

  final LeaderboardEntry entry;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      label: <String>[
        'Rank ${entry.rank}',
        entry.username,
        '${entry.points} points',
        if (entry.isBot) 'bot entry, not a real person',
        if (isMe) 'you',
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        color: isMe
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 34,
              child: Text(
                '${entry.rank}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            _Avatar(entry: entry, isMe: isMe),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      entry.username,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: isMe ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  if (isMe) ...<Widget>[
                    const SizedBox(width: 6),
                    Text(
                      '(you)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                  if (entry.isBot) ...<Widget>[
                    const SizedBox(width: 8),
                    const BotChip(),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${entry.points}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
            const SizedBox(width: 2),
            Text(
              'pts',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The non-negotiable bot label (CLAUDE.md rule 7): a padding entry must never
/// read as a real person. Text, not just a colour or an icon.
class BotChip extends StatelessWidget {
  const BotChip({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        'BOT',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry, required this.isMe});

  final LeaderboardEntry entry;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // A bot gets a machine glyph rather than an initial, so the distinction
    // survives even if the chip is scrolled out of view.
    if (entry.isBot) {
      return Container(
        height: 30,
        width: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Icon(
          Icons.smart_toy_outlined,
          size: 17,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Container(
      height: 30,
      width: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMe
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        entry.initial,
        style: theme.textTheme.labelLarge?.copyWith(
          color: isMe
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
