import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/data/models/app_user.dart';
import 'package:optionsschool/data/models/education_level.dart';
import 'package:optionsschool/data/models/leaderboard.dart';
import 'package:optionsschool/data/models/lesson_progress.dart';
import 'package:optionsschool/data/repositories/leaderboard_repo.dart';
import 'package:optionsschool/data/repositories/progress_repo.dart';
import 'package:optionsschool/engagement/streak.dart';
import 'package:optionsschool/features/leaderboard/leaderboard_screen.dart';
import 'package:optionsschool/features/leaderboard/widgets/leaderboard_row.dart';
import 'package:optionsschool/providers/auth_controller.dart';
import 'package:optionsschool/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Ranks screen, judged mainly on the promises it has to keep:
/// bots are labelled, a solo board says so, and an outage is not dressed up as
/// an empty leaderboard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppUser me = AppUser(
    id: 'u-me',
    username: 'ana',
    educationLevel: EducationLevel.undergraduate,
    createdAt: DateTime(2026, 1, 1),
  );

  Future<void> pump(
    WidgetTester tester, {
    required LeaderboardRepo repo,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          leaderboardRepoProvider.overrideWithValue(repo),
          progressRepoProvider.overrideWithValue(_EmptyProgressRepo()),
          authControllerProvider.overrideWith(() => _StubAuthController(me)),
        ],
        child: const MaterialApp(home: Scaffold(body: LeaderboardView())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a bot entry is labelled BOT and never reads as a person', (
    tester,
  ) async {
    await pump(
      tester,
      repo: _StubLeaderboardRepo(
        const LeaderboardBoard(
          period: LeaderboardPeriod.week,
          entries: <LeaderboardEntry>[
            LeaderboardEntry(
              rank: 1,
              username: 'ana',
              points: 140,
              isBot: false,
              userId: 'u-me',
            ),
            LeaderboardEntry(
              rank: 2,
              username: 'practice-bot',
              points: 90,
              isBot: true,
            ),
          ],
          standing: LeaderboardStanding(
            rank: 1,
            points: 140,
            totalPlayers: 2,
          ),
        ),
      ),
    );

    expect(find.byType(BotChip), findsOneWidget);
    expect(find.text('BOT'), findsOneWidget);
    // And the footnote spells out what the label means.
    expect(
      find.textContaining('not real people'),
      findsOneWidget,
    );
  });

  testWidgets('no bots means no bot small print', (tester) async {
    await pump(
      tester,
      repo: _StubLeaderboardRepo(
        const LeaderboardBoard(
          period: LeaderboardPeriod.allTime,
          entries: <LeaderboardEntry>[
            LeaderboardEntry(
              rank: 1,
              username: 'ana',
              points: 140,
              isBot: false,
              userId: 'u-me',
            ),
            LeaderboardEntry(
              rank: 2,
              username: 'ben',
              points: 90,
              isBot: false,
              userId: 'u-ben',
            ),
          ],
        ),
      ),
    );

    expect(find.byType(BotChip), findsNothing);
    expect(find.textContaining('not real people'), findsNothing);
  });

  testWidgets('the learner’s own row is marked, and their rank shown up top', (
    tester,
  ) async {
    await pump(
      tester,
      repo: _StubLeaderboardRepo(
        const LeaderboardBoard(
          period: LeaderboardPeriod.week,
          entries: <LeaderboardEntry>[
            LeaderboardEntry(
              rank: 1,
              username: 'ben',
              points: 200,
              isBot: false,
              userId: 'u-ben',
            ),
            LeaderboardEntry(
              rank: 2,
              username: 'ana',
              points: 140,
              isBot: false,
              userId: 'u-me',
            ),
          ],
          standing: LeaderboardStanding(
            rank: 2,
            points: 140,
            totalPlayers: 2,
          ),
        ),
      ),
    );

    expect(find.text('(you)'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    // "on the board", not "learners" — the count can include labelled bots.
    expect(find.textContaining('of 2 on the board'), findsOneWidget);
  });

  testWidgets('a board with no server says so instead of implying solitude', (
    tester,
  ) async {
    await pump(
      tester,
      repo: _StubLeaderboardRepo(
        const LeaderboardBoard(
          period: LeaderboardPeriod.week,
          isServerBacked: false,
          entries: <LeaderboardEntry>[
            LeaderboardEntry(
              rank: 1,
              username: 'ana',
              points: 55,
              isBot: false,
              userId: 'u-me',
            ),
          ],
          standing: LeaderboardStanding(rank: 1, points: 55, totalPlayers: 1),
        ),
      ),
    );

    expect(
      find.textContaining('Standings need a server connection'),
      findsOneWidget,
    );
    expect(find.textContaining('Nobody else has been invented'), findsOneWidget);
  });

  testWidgets('an outage shows an error and a retry, not an empty board', (
    tester,
  ) async {
    await pump(
      tester,
      repo: _FailingLeaderboardRepo(
        const LeaderboardException('Can’t reach the server, so standings '
            'aren’t available right now.'),
      ),
    );

    expect(find.textContaining('Can’t reach the server'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Try again'), findsOneWidget);
    // Crucially: nothing that could be read as "you are alone here".
    expect(find.textContaining('only learner'), findsNothing);
  });

  testWidgets('switching period re-reads the board', (tester) async {
    final _RecordingLeaderboardRepo repo = _RecordingLeaderboardRepo();
    await pump(tester, repo: repo);

    expect(repo.requested.first, LeaderboardPeriod.week);
    expect(repo.requested, isNot(contains(LeaderboardPeriod.allTime)));

    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();

    expect(repo.requested.last, LeaderboardPeriod.allTime);
    // The heading also states the cap, so a learner below it can tell a
    // truncated board from a small one.
    expect(find.text('ALL TIME · TOP $kLeaderboardPageSize'), findsOneWidget);
    expect(find.textContaining('every point you have earned'), findsOneWidget);
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _StubLeaderboardRepo implements LeaderboardRepo {
  const _StubLeaderboardRepo(this._board);

  final LeaderboardBoard _board;

  @override
  Future<LeaderboardBoard> load({
    required LeaderboardPeriod period,
    int limit = 50,
  }) async => _board;
}

class _FailingLeaderboardRepo implements LeaderboardRepo {
  const _FailingLeaderboardRepo(this._error);

  final Object _error;

  @override
  Future<LeaderboardBoard> load({
    required LeaderboardPeriod period,
    int limit = 50,
  }) async => throw _error;
}

class _RecordingLeaderboardRepo implements LeaderboardRepo {
  final List<LeaderboardPeriod> requested = <LeaderboardPeriod>[];

  @override
  Future<LeaderboardBoard> load({
    required LeaderboardPeriod period,
    int limit = 50,
  }) async {
    requested.add(period);
    return LeaderboardBoard(
      period: period,
      entries: const <LeaderboardEntry>[
        LeaderboardEntry(
          rank: 1,
          username: 'ana',
          points: 10,
          isBot: false,
          userId: 'u-me',
        ),
      ],
    );
  }
}

class _StubAuthController extends AuthController {
  _StubAuthController(this._user);

  final AppUser _user;

  @override
  Future<AppUser?> build() async => _user;
}

class _EmptyProgressRepo implements ProgressRepo {
  @override
  Future<void> clear(String userId) async {}

  @override
  Future<Map<String, LessonProgress>> loadAll(String userId) async =>
      <String, LessonProgress>{};

  @override
  Future<LessonProgress?> loadLesson({
    required String userId,
    required String lessonId,
  }) async => null;

  @override
  Future<StreakState?> loadStreak(String userId) async => null;

  @override
  Future<void> saveLesson({
    required String userId,
    required LessonProgress progress,
  }) async {}

  @override
  Future<void> saveStreak({
    required String userId,
    required StreakState streak,
  }) async {}

  @override
  Future<int> totalPoints(String userId) async => 0;
}
