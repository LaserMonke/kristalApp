import '../models/leaderboard.dart';

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
    int limit = 50,
  });
}

class LeaderboardException implements Exception {
  const LeaderboardException(this.message);
  final String message;

  @override
  String toString() => message;
}
