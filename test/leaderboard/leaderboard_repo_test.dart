import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optionsschool/data/local/local_leaderboard_repo.dart';
import 'package:optionsschool/data/local/local_progress_repo.dart';
import 'package:optionsschool/data/models/app_user.dart';
import 'package:optionsschool/data/models/education_level.dart';
import 'package:optionsschool/data/models/leaderboard.dart';
import 'package:optionsschool/data/models/lesson_progress.dart';
import 'package:optionsschool/data/repositories/auth_repo.dart';
import 'package:optionsschool/data/repositories/leaderboard_repo.dart';
import 'package:optionsschool/data/supabase/supabase_leaderboard_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// The leaderboard data layer, including the rules that keep it honest:
/// bots stay flagged, and with no server nobody is invented to fill the board.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Supabase leaderboard', () {
    test('maps a page and the caller’s own standing', () async {
      final SupabaseLeaderboardRepo repo = _repo((http.BaseRequest request) {
        if (request.url.path.endsWith('leaderboard_page')) {
          return _json(<Map<String, dynamic>>[
            <String, dynamic>{
              'rank': 1,
              'user_id': 'u-ana',
              'username': 'ana',
              'points': 140,
              'is_bot': false,
            },
            <String, dynamic>{
              'rank': 2,
              'user_id': null,
              'username': 'practice-bot',
              'points': 90,
              'is_bot': true,
            },
          ]);
        }
        return _json(<Map<String, dynamic>>[
          <String, dynamic>{'rank': 2, 'points': 90, 'total_players': 2},
        ]);
      });

      final LeaderboardBoard board = await repo.load(
        period: LeaderboardPeriod.week,
      );

      expect(board.entries, hasLength(2));
      expect(board.entries.first.username, 'ana');
      expect(board.entries.first.isBot, isFalse);
      expect(board.entries.last.isBot, isTrue);
      expect(board.hasBots, isTrue);
      expect(board.standing?.rank, 2);
      expect(board.standing?.totalPlayers, 2);
    });

    test('a learner with no ranking yet gets a board without a standing', () async {
      final SupabaseLeaderboardRepo repo = _repo(
        (http.BaseRequest request) => _json(const <Map<String, dynamic>>[]),
      );

      final LeaderboardBoard board = await repo.load(
        period: LeaderboardPeriod.allTime,
      );
      expect(board.entries, isEmpty);
      expect(board.standing, isNull);
    });

    test('the period is sent as the value the SQL functions expect', () async {
      final List<String> bodies = <String>[];
      final SupabaseLeaderboardRepo repo = _repo((http.BaseRequest request) {
        bodies.add(request is http.Request ? request.body : '');
        return _json(const <Map<String, dynamic>>[]);
      });

      await repo.load(period: LeaderboardPeriod.week);
      expect(bodies.first, contains('"period":"week"'));

      bodies.clear();
      await repo.load(period: LeaderboardPeriod.allTime);
      expect(bodies.first, contains('"period":"all_time"'));
    });

    test('being offline reads as unavailable, never as an empty board', () async {
      // An empty leaderboard would say "nobody else is learning", which is a
      // different claim from "we could not ask".
      final SupabaseLeaderboardRepo repo = _repo(
        (http.BaseRequest request) => throw http.ClientException('offline'),
      );

      await expectLater(
        repo.load(period: LeaderboardPeriod.week),
        throwsA(
          isA<LeaderboardException>().having(
            (LeaderboardException e) => e.message,
            'message',
            contains('Can’t reach the server'),
          ),
        ),
      );
    });

    test('a missing migration is reported as not set up', () async {
      final SupabaseLeaderboardRepo repo = _repo(
        (http.BaseRequest request) => _json(<String, dynamic>{
          'code': 'PGRST202',
          'message': 'Could not find the function',
        }, status: 404),
      );

      await expectLater(
        repo.load(period: LeaderboardPeriod.week),
        throwsA(
          isA<LeaderboardException>().having(
            (LeaderboardException e) => e.message,
            'message',
            contains('aren’t set up'),
          ),
        ),
      );
    });

    /// The server refuses callers without a session (42501). It has to check
    /// that itself: these are SECURITY DEFINER functions, so RLS does not
    /// apply to them, and the grants alone turned out not to be enough — see
    /// `supabase/migrations/20260801090000_phase7_lockdown.sql`.
    test('a refused unauthenticated call asks the learner to sign in', () async {
      final SupabaseLeaderboardRepo repo = _repo(
        (http.BaseRequest request) => _json(<String, dynamic>{
          'code': '42501',
          'message': 'Standings are only available to signed-in learners.',
        }, status: 403),
      );

      await expectLater(
        repo.load(period: LeaderboardPeriod.allTime),
        throwsA(
          isA<LeaderboardException>().having(
            (LeaderboardException e) => e.message,
            'message',
            contains('Sign in'),
          ),
        ),
      );
    });

    /// Only the caller's own id comes back now; every other row's is null.
    /// The row for "me" must still be identifiable, and nobody else's must be.
    test('withheld user ids do not break the "this is you" highlight', () async {
      final SupabaseLeaderboardRepo repo = _repo(
        (http.BaseRequest request) => _json(<dynamic>[
          <String, dynamic>{
            'rank': 1,
            'user_id': null,
            'username': 'someone-else',
            'points': 90,
            'is_bot': false,
          },
          <String, dynamic>{
            'rank': 2,
            'user_id': 'me-123',
            'username': 'me',
            'points': 40,
            'is_bot': false,
          },
        ]),
      );

      final LeaderboardBoard board = await repo.load(
        period: LeaderboardPeriod.allTime,
      );

      expect(board.entries, hasLength(2));
      expect(board.entries.first.userId, isNull);
      expect(board.entries.first.isMe('me-123'), isFalse);
      expect(board.entries.last.isMe('me-123'), isTrue);
      // A withheld id must never accidentally match a null current user.
      expect(board.entries.first.isMe(null), isFalse);
    });
  });

  group('local leaderboard (no server)', () {
    Future<LocalLeaderboardRepo> localRepo({
      required Map<String, LessonProgress> progress,
      AppUser? user,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LocalProgressRepo store = LocalProgressRepo(prefs);

      final AppUser signedIn =
          user ??
          AppUser(
            id: 'u-me',
            username: 'ana',
            educationLevel: EducationLevel.undergraduate,
            createdAt: DateTime(2026, 1, 1),
          );
      for (final LessonProgress p in progress.values) {
        await store.saveLesson(userId: signedIn.id, progress: p);
      }

      return LocalLeaderboardRepo(auth: _StubAuth(signedIn), progress: store);
    }

    test('signed out, the board is empty rather than guessing at a name', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final LocalLeaderboardRepo repo = LocalLeaderboardRepo(
        auth: _StubAuth(null),
        progress: LocalProgressRepo(prefs),
      );

      final LeaderboardBoard board = await repo.load(
        period: LeaderboardPeriod.week,
      );
      expect(board.entries, isEmpty);
      expect(board.standing, isNull);
      expect(board.isServerBacked, isFalse);
    });

    test('contains only the learner, and admits it is not server-backed', () async {
      final LocalLeaderboardRepo repo = await localRepo(
        progress: <String, LessonProgress>{
          'a': const LessonProgress(lessonId: 'a', pointsEarned: 55),
        },
      );

      final LeaderboardBoard board = await repo.load(
        period: LeaderboardPeriod.allTime,
      );

      expect(board.isServerBacked, isFalse);
      expect(board.entries, hasLength(1));
      expect(board.entries.single.username, 'ana');
      expect(board.entries.single.points, 55);
      expect(board.isSolo, isTrue);
      // The whole point: no invented rivals (CLAUDE.md rule 7).
      expect(board.hasBots, isFalse);
    });

    test('weekly counts only lessons finished since Monday', () async {
      final DateTime now = DateTime.now();
      final DateTime monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - DateTime.monday));

      final LocalLeaderboardRepo repo = await localRepo(
        progress: <String, LessonProgress>{
          'old': LessonProgress(
            lessonId: 'old',
            pointsEarned: 30,
            completedAt: monday.subtract(const Duration(days: 3)),
          ),
          'new': LessonProgress(
            lessonId: 'new',
            pointsEarned: 45,
            completedAt: monday.add(const Duration(hours: 2)),
          ),
        },
      );

      final LeaderboardBoard week = await repo.load(
        period: LeaderboardPeriod.week,
      );
      expect(week.entries.single.points, 45);

      final LeaderboardBoard allTime = await repo.load(
        period: LeaderboardPeriod.allTime,
      );
      expect(allTime.entries.single.points, 75);
    });

    test('a lesson with no completion date never counts toward the week', () async {
      final LocalLeaderboardRepo repo = await localRepo(
        progress: <String, LessonProgress>{
          'partial': const LessonProgress(lessonId: 'partial', pointsEarned: 20),
        },
      );

      expect(
        (await repo.load(period: LeaderboardPeriod.week)).entries.single.points,
        0,
      );
    });
  });

  group('entry model', () {
    test('only a real, id-matched entry is "me"', () {
      const LeaderboardEntry me = LeaderboardEntry(
        rank: 1,
        username: 'ana',
        points: 10,
        isBot: false,
        userId: 'u-me',
      );
      const LeaderboardEntry bot = LeaderboardEntry(
        rank: 2,
        username: 'bot',
        points: 5,
        isBot: true,
        userId: 'u-me',
      );

      expect(me.isMe('u-me'), isTrue);
      expect(me.isMe('someone-else'), isFalse);
      expect(me.isMe(null), isFalse);
      // A bot can never be the signed-in learner, whatever id it carries.
      expect(bot.isMe('u-me'), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

SupabaseLeaderboardRepo _repo(
  Future<http.StreamedResponse> Function(http.BaseRequest request) responder,
) {
  final sb.SupabaseClient client = sb.SupabaseClient(
    'https://stub.supabase.co',
    'stub-key',
    httpClient: _FakeHttpClient(responder),
  );
  addTearDown(client.dispose);
  return SupabaseLeaderboardRepo(client);
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._responder);

  final Future<http.StreamedResponse> Function(http.BaseRequest) _responder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.StreamedResponse response = await _responder(request);
    return http.StreamedResponse(
      response.stream,
      response.statusCode,
      contentLength: response.contentLength,
      headers: response.headers,
      request: request,
    );
  }
}

Future<http.StreamedResponse> _json(Object? payload, {int status = 200}) async {
  final List<int> bytes = utf8.encode(jsonEncode(payload));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    status,
    contentLength: bytes.length,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

class _StubAuth implements AuthRepo {
  _StubAuth(this._user);

  final AppUser? _user;

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() => const Stream<AppUser?>.empty();

  @override
  Future<AppUser?> restoreSession() async => _user;

  @override
  Future<AppUser> signIn({
    required String username,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AppUser> signUp({
    required String username,
    required String password,
    required EducationLevel educationLevel,
  }) => throw UnimplementedError();

  @override
  Future<void> signOut() async {}
}
