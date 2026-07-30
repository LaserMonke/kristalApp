import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/leaderboard.dart';
import '../repositories/leaderboard_repo.dart';
import 'supabase_error_messages.dart';
import 'supabase_tables.dart';

/// The real leaderboard, read through the two SECURITY DEFINER functions added
/// in the Phase 7 migration.
///
/// Those functions are the only cross-user read in the app. They return a
/// display name, a point total and an is_bot flag — never a profile or progress
/// row — so the RLS lockdown from Phase 6 stays intact.
///
/// Not cached offline, deliberately: a stale ranking presented as current would
/// be a lie about other people's scores. With no connection the screen says it
/// cannot reach the server (CLAUDE.md rule 8).
class SupabaseLeaderboardRepo implements LeaderboardRepo {
  const SupabaseLeaderboardRepo(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<LeaderboardBoard> load({
    required LeaderboardPeriod period,
    int limit = 50,
  }) async {
    try {
      // Two round trips rather than one: the page is capped, so a learner
      // outside the top N still needs their own rank looked up separately.
      final List<dynamic> rows = await _client.rpc<List<dynamic>>(
        Db.leaderboardPageFn,
        params: <String, dynamic>{
          'period': period.wire,
          'limit_count': limit,
        },
      );

      final List<dynamic> mine = await _client.rpc<List<dynamic>>(
        Db.leaderboardStandingFn,
        params: <String, dynamic>{'period': period.wire},
      );

      return LeaderboardBoard(
        period: period,
        entries: <LeaderboardEntry>[
          for (final dynamic row in rows)
            LeaderboardEntry.fromRow(row as Map<String, dynamic>),
        ],
        // Absent until the learner has a profile row to rank.
        standing: mine.isEmpty
            ? null
            : LeaderboardStanding.fromRow(mine.first as Map<String, dynamic>),
      );
    } catch (error) {
      if (isOfflineError(error)) {
        throw const LeaderboardException(
          'Can’t reach the server, so standings aren’t available right now.',
        );
      }
      if (error is sb.PostgrestException && error.code == 'PGRST202') {
        // The function is missing: the Phase 7 migration has not been applied.
        throw const LeaderboardException(
          'Standings aren’t set up on this backend yet.',
        );
      }
      throw const LeaderboardException('Couldn’t load standings.');
    }
  }
}
