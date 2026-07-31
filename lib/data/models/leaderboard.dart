/// Leaderboard models (Phase 7). Pure Dart — no Flutter, no Supabase.
library;

/// Which window a ranking covers.
enum LeaderboardPeriod {
  /// Points from lessons first finished since the start of this week.
  week('week', 'This week'),

  /// Every point ever earned.
  allTime('all_time', 'All time');

  const LeaderboardPeriod(this.wire, this.label);

  /// The value the `leaderboard_*` SQL functions expect.
  final String wire;

  final String label;
}

/// One row of the ranking.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.username,
    required this.points,
    required this.isBot,
    this.userId,
  });

  /// Shared by ties: two learners on the same points are both 4th, and the
  /// next one down is 6th.
  final int rank;

  final String username;
  final int points;

  /// True for a padding entry. The UI MUST label these — CLAUDE.md rule 7
  /// forbids presenting a bot score as a real person.
  final bool isBot;

  /// The caller's OWN id, and null for every other row.
  ///
  /// The server deliberately withholds other learners' ids: highlighting
  /// "you" in the list is the only thing the client ever needed one for, so
  /// sending the rest would be handing out stable identifiers for no purpose
  /// (CLAUDE.md rule 6). Null for bots, which have no user at all.
  final String? userId;

  bool isMe(String? currentUserId) =>
      !isBot && userId != null && userId == currentUserId;

  /// First letter, for the row avatar.
  String get initial =>
      username.isEmpty ? '?' : username.substring(0, 1).toUpperCase();

  factory LeaderboardEntry.fromRow(Map<String, dynamic> row) {
    return LeaderboardEntry(
      rank: (row['rank'] as num?)?.toInt() ?? 0,
      username: (row['username'] as String?)?.trim() ?? 'learner',
      points: (row['points'] as num?)?.toInt() ?? 0,
      isBot: row['is_bot'] as bool? ?? false,
      userId: row['user_id'] as String?,
    );
  }
}

/// Where the signed-in learner sits, even when they are off the visible page.
class LeaderboardStanding {
  const LeaderboardStanding({
    required this.rank,
    required this.points,
    required this.totalPlayers,
  });

  final int rank;
  final int points;

  /// Everyone on the board, bots included — which is why the UI says "on the
  /// board" rather than "learners".
  final int totalPlayers;

  factory LeaderboardStanding.fromRow(Map<String, dynamic> row) {
    return LeaderboardStanding(
      rank: (row['rank'] as num?)?.toInt() ?? 0,
      points: (row['points'] as num?)?.toInt() ?? 0,
      totalPlayers: (row['total_players'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A rendered leaderboard: the visible page plus the caller's own standing.
class LeaderboardBoard {
  const LeaderboardBoard({
    required this.period,
    required this.entries,
    this.standing,
    this.isServerBacked = true,
  });

  final LeaderboardPeriod period;
  final List<LeaderboardEntry> entries;

  /// Null when the learner has no ranking yet (no profile row on the server).
  final LeaderboardStanding? standing;

  /// False when there is no backend, so the board can only ever contain the
  /// learner themselves. The screen says so instead of implying an empty
  /// leaderboard means nobody else is learning.
  final bool isServerBacked;

  /// True when the learner is the only entry — a real state for a new install,
  /// and not an error.
  bool get isSolo => entries.length <= 1;

  bool get hasBots => entries.any((LeaderboardEntry e) => e.isBot);
}
