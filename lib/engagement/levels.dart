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

/// Thresholds are sized against the shipped curriculum: six lessons, each
/// worth up to 75 points (20 deck + 4 × 10 answers + 15 perfect bonus), 450 in
/// total. Graduate at 360 means "every deck finished and every question
/// eventually answered correctly" — reachable by persistence, since the best
/// Q&A attempt is what counts. A content test asserts reachability.
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
