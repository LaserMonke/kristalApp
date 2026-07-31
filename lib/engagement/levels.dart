/// The level ladder (Phase 5). Pure Dart, no Flutter imports.
///
/// Levels are cosmetic recognition of accumulated points — nothing in the app
/// is locked behind them (lessons unlock on the previous Q&A, per CLAUDE.md).
/// The ladder tops out at Graduate; the completion certificate is separate and
/// is earned by finishing every lesson's Q&A, not by points.
library;

class Level {
  const Level({
    required this.rank,
    required this.name,
    required this.minPoints,
    required this.iconName,
  });

  /// 1-based position on the ladder.
  final int rank;
  final String name;
  final int minPoints;

  /// Badge glyph name, resolved to an IconData by the UI through a fixed
  /// compile-time map (same pattern as lesson icons — tree-shaking safe).
  final String iconName;
}

/// Thresholds were sized against the original curriculum: six lessons, each
/// worth up to 75 points (20 deck + 4 × 10 answers + 15 perfect bonus), 450 in
/// total, with Graduate at 360 meaning "every deck finished and every question
/// eventually answered correctly". A content test asserts reachability.
///
/// PHASE 8 ADDED THREE LESSONS, taking the curriculum to 675 points, so
/// Graduate is now reached at roughly two-thirds of the way through rather
/// than at the end. The thresholds were deliberately NOT rescaled to match.
///
/// Rescaling would have demoted every learner who had already earned a level —
/// someone who woke up as an Analyst and found themselves an Apprentice again,
/// having done nothing wrong and lost nothing. Taking recognition back to
/// preserve a ratio is exactly the sort of thing CLAUDE.md rule 9 rules out,
/// and the ratio was never the point.
///
/// Nothing is misrepresented by leaving them: levels are cosmetic recognition
/// of points accumulated, and they still are. The CERTIFICATE — the claim that
/// actually says a learner has finished the course — is gated on completing
/// every lesson's Q&A, so it tracked the new lessons automatically the moment
/// they shipped, and still means what it says.
const List<Level> levels = <Level>[
  Level(rank: 1, name: 'Newcomer', minPoints: 0, iconName: 'seedling'),
  Level(rank: 2, name: 'Observer', minPoints: 40, iconName: 'eye'),
  Level(rank: 3, name: 'Apprentice', minPoints: 100, iconName: 'book'),
  Level(rank: 4, name: 'Analyst', minPoints: 160, iconName: 'chart'),
  Level(rank: 5, name: 'Strategist', minPoints: 230, iconName: 'strategy'),
  Level(rank: 6, name: 'Hedger', minPoints: 300, iconName: 'shield'),
  Level(rank: 7, name: 'Graduate', minPoints: 360, iconName: 'medal'),
];

Level levelForPoints(int points) {
  Level current = levels.first;
  for (final Level level in levels) {
    if (points >= level.minPoints) current = level;
  }
  return current;
}

/// The next rung up, or null at the top of the ladder.
Level? nextLevelForPoints(int points) {
  final Level current = levelForPoints(points);
  return current.rank < levels.length ? levels[current.rank] : null;
}

/// Fraction of the way from the current level to the next, 1.0 at the top.
double progressTowardNextLevel(int points) {
  final Level current = levelForPoints(points);
  final Level? next = nextLevelForPoints(points);
  if (next == null) return 1;
  return ((points - current.minPoints) / (next.minPoints - current.minPoints))
      .clamp(0.0, 1.0);
}
