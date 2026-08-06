import '../models/leaderboard.dart';

/// How many ranks the board shows.
///
/// One constant rather than a default repeated at each layer, because three
/// copies of "50" is three chances for the local and server boards to disagree
/// about how long a board is.
///
/// A learner's own standing is fetched separately and always shown, so a short
/// board does not hide anyone from themselves — someone ranked 340th still
/// sees 340th, they just do not scroll past 320 strangers to reach it.
const int kLeaderboardPageSize = 20;

/// Rankings across learners (Phase 7).
///
/// Kept behind an interface like every other repository, so the screen is
/// identical whether the board came from Postgres or from the device.
abstract interface class LeaderboardRepo {
  /// The visible page plus the signed-in learner's own standing.
  ///
  /// Throws [LeaderboardException] with a message safe to show verbatim.
  Future<LeaderboardBoard> load({
    required LeaderboardPeriod period,
    int limit = kLeaderboardPageSize,
  });
}

class LeaderboardException implements Exception {
  const LeaderboardException(this.message);
  final String message;

  @override
  String toString() => message;
}
