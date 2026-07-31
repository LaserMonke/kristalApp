import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/leaderboard.dart';
import '../../providers/leaderboard_providers.dart';
import '../../providers/market_providers.dart';
import 'widgets/leaderboard_row.dart';
import 'widgets/standing_card.dart';

/// The Ranks tab — standings across real learners (Phase 7).
///
/// Three honesty rules shape this screen:
///   * Bot entries are labelled as bots (CLAUDE.md rule 7). Nothing here
///     invents a rival to make a new board look busy; a board of one says so.
///   * The weekly window is the SERVER's week (Monday 00:00 UTC), and the
///     screen says that rather than implying it follows the phone's clock.
///   * Points are computed by the database, not reported by the app, so a rank
///     cannot be inflated by a modified client.
/// The Ranks content, without a Scaffold — it lives as a tab inside the Learn
/// screen (Phase 9 restructure), which supplies the app bar.
class LeaderboardView extends ConsumerWidget {
  const LeaderboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LeaderboardPeriod period = ref.watch(leaderboardPeriodProvider);
    final AsyncValue<LeaderboardBoard> board = ref.watch(
      leaderboardProvider(period),
    );

    return Column(
      children: <Widget>[
        _PeriodSelector(
          period: period,
          onChanged: (LeaderboardPeriod next) =>
              ref.read(leaderboardPeriodProvider.notifier).select(next),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(leaderboardProvider(period));
              try {
                await ref.read(leaderboardProvider(period).future);
              } catch (_) {
                // Swallowed only so a pull-to-refresh over a dead network
                // ends its spinner. The error state below does the telling.
              }
            },
            child: board.when(
              loading: () => const _Centered(
                child: SizedBox(
                  height: 26,
                  width: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
              error: (Object error, _) => _Message(
                icon: Icons.cloud_off_outlined,
                text: leaderboardErrorMessage(error),
                onRetry: () => ref.invalidate(leaderboardProvider(period)),
              ),
              data: (LeaderboardBoard data) => _Board(board: data),
            ),
          ),
        ),
      ],
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.board});

  final LeaderboardBoard board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String? currentUserId = ref.watch(currentUserIdProvider);
    final int bonus = ref.watch(marketBonusPointsProvider);
    final String? note = leaderboardEmptyMessage(board);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: <Widget>[
        if (board.standing != null)
          StandingCard(
            standing: board.standing!,
            period: board.period,
            bonusPoints: bonus,
          ),
        if (note != null) ...<Widget>[
          const SizedBox(height: 12),
          _Note(note),
        ],
        if (board.entries.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Text(
            board.period == LeaderboardPeriod.week
                ? 'THIS WEEK'
                : 'ALL TIME',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < board.entries.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  LeaderboardRow(
                    entry: board.entries[i],
                    isMe: board.entries[i].isMe(currentUserId),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        _Footnote(board: board, bonusPoints: bonus),
      ],
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.period, required this.onChanged});

  final LeaderboardPeriod period;
  final ValueChanged<LeaderboardPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SegmentedButton<LeaderboardPeriod>(
        segments: <ButtonSegment<LeaderboardPeriod>>[
          for (final LeaderboardPeriod option in LeaderboardPeriod.values)
            ButtonSegment<LeaderboardPeriod>(
              value: option,
              label: Text(option.label),
            ),
        ],
        selected: <LeaderboardPeriod>{period},
        showSelectedIcon: false,
        onSelectionChanged: (Set<LeaderboardPeriod> selection) =>
            onChanged(selection.first),
      ),
    );
  }
}

/// The small print. Explicit about where the numbers come from and what the
/// week actually means — a leaderboard that hides its rules invites the
/// suspicion that it has none.
class _Footnote extends StatelessWidget {
  const _Footnote({required this.board, this.bonusPoints = 0});

  final LeaderboardBoard board;
  final int bonusPoints;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final String text = <String>[
      if (board.period == LeaderboardPeriod.week)
        'This week counts points from lessons you finished since Monday '
            '00:00 UTC.'
      else
        'All time counts every point you have earned.',
      'Points are worked out on the server from your lesson and Q&A records.',
      if (bonusPoints > 0)
        'Your practice-market gains add $bonusPoints points to your own total '
            'on this device; other learners are ranked on lesson points.',
      'Equal scores share a rank.',
      if (board.hasBots)
        'Entries marked BOT are practice placeholders, not real people.',
    ].join(' ');

    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.45,
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 34, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Centres content while staying scrollable, so `RefreshIndicator` still works
/// on the loading and error states.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
