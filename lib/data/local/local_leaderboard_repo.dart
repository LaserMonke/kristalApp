import '../models/app_user.dart';
import '../models/leaderboard.dart';
import '../models/lesson_progress.dart';
import '../repositories/auth_repo.dart';
import '../repositories/leaderboard_repo.dart';
import '../repositories/progress_repo.dart';

/// The leaderboard with no server behind it.
///
/// It can honestly contain exactly one entry — the learner on this device — so
/// that is what it returns. It does NOT invent rivals to make the screen look
/// populated: fabricated scores presented as other people would break
/// CLAUDE.md rule 7, and the screen instead explains that standings need a
/// server connection.
class LocalLeaderboardRepo implements LeaderboardRepo {
  const LocalLeaderboardRepo({
    required AuthRepo auth,
    required ProgressRepo progress,
    // ignore: prefer_initializing_formals
  }) : _auth = auth,
       // ignore: prefer_initializing_formals
       _progress = progress;

  final AuthRepo _auth;
  final ProgressRepo _progress;

  @override
  Future<LeaderboardBoard> load({
    required LeaderboardPeriod period,
    int limit = kLeaderboardPageSize,
  }) async {
    final AppUser? user = _auth.currentUser;
    if (user == null) {
      return LeaderboardBoard(
        period: period,
        entries: const <LeaderboardEntry>[],
        isServerBacked: false,
      );
    }

    final Map<String, LessonProgress> all = await _progress.loadAll(user.id);
    final int points = _points(all, period);

    return LeaderboardBoard(
      period: period,
      isServerBacked: false,
      entries: <LeaderboardEntry>[
        LeaderboardEntry(
          rank: 1,
          username: user.username,
          points: points,
          isBot: false,
          userId: user.id,
        ),
      ],
      standing: LeaderboardStanding(
        rank: 1,
        points: points,
        totalPlayers: 1,
      ),
    );
  }

  /// Mirrors the SQL definition of the two periods: all-time is every point
  /// earned, weekly counts only lessons FIRST finished since the start of this
  /// week. Local time here, UTC on the server — the difference is at most a few
  /// hours around the boundary and the UI labels the server's rule.
  int _points(Map<String, LessonProgress> all, LeaderboardPeriod period) {
    final DateTime weekStart = _startOfWeek(DateTime.now());

    return all.values.fold<int>(0, (int sum, LessonProgress p) {
      if (period == LeaderboardPeriod.week) {
        final DateTime? done = p.completedAt;
        if (done == null || done.isBefore(weekStart)) return sum;
      }
      return sum + p.pointsEarned;
    });
  }

  /// Monday 00:00, matching `date_trunc('week', …)` in Postgres.
  static DateTime _startOfWeek(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }
}
