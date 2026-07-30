import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/leaderboard.dart';
import '../data/repositories/leaderboard_repo.dart';
import 'auth_controller.dart';
import 'progress_controller.dart';
import 'repository_providers.dart';

/// Which window the Ranks tab is showing. Lives outside the screen so the
/// choice survives a tab switch.
class LeaderboardPeriodController extends Notifier<LeaderboardPeriod> {
  @override
  LeaderboardPeriod build() => LeaderboardPeriod.week;

  void select(LeaderboardPeriod period) => state = period;
}

final NotifierProvider<LeaderboardPeriodController, LeaderboardPeriod>
leaderboardPeriodProvider =
    NotifierProvider<LeaderboardPeriodController, LeaderboardPeriod>(
      LeaderboardPeriodController.new,
    );

/// The board for one period.
///
/// Watches the learner's own progress so finishing a lesson re-reads the
/// ranking — otherwise the screen would keep showing a rank the learner has
/// already climbed past.
// Type inferred: Riverpod does not export the family's concrete type.
final leaderboardProvider =
    FutureProvider.family<LeaderboardBoard, LeaderboardPeriod>((
      Ref ref,
      LeaderboardPeriod period,
    ) {
      ref.watch(progressControllerProvider);
      return ref.watch(leaderboardRepoProvider).load(period: period);
    });

/// The signed-in learner's id, for highlighting their own row.
final Provider<String?> currentUserIdProvider = Provider<String?>(
  (Ref ref) => ref.watch(currentUserProvider)?.id,
);

/// Message to show instead of a board, or null when there is one to show.
String? leaderboardEmptyMessage(LeaderboardBoard board) {
  if (board.entries.isEmpty) {
    return board.isServerBacked
        ? 'No rankings yet. Finish a lesson to get on the board.'
        : 'Sign in to see where you stand.';
  }
  if (!board.isServerBacked) {
    return 'Standings need a server connection, so this is just you. Nobody '
        'else has been invented to fill the gap.';
  }
  if (board.isSolo) {
    return 'You’re the only learner on the board so far.';
  }
  return null;
}

/// A [LeaderboardException] message, or a generic line for anything else.
String leaderboardErrorMessage(Object error) => error is LeaderboardException
    ? error.message
    : 'Couldn’t load standings.';
