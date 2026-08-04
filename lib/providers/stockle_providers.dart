import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../games/stockle/stockle_engine.dart';
import 'repository_providers.dart';

/// The playable ticker set, loaded once from the bundled asset.
final FutureProvider<StockleDictionary> stockleDictionaryProvider =
    FutureProvider<StockleDictionary>((Ref ref) async {
      final String raw = await rootBundle.loadString(
        'assets/games/nasdaq100_4letter.json',
      );
      return StockleDictionary.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    });

/// Today's puzzle number, in UTC so it turns over at the same instant for
/// everyone rather than at each player's local midnight.
final Provider<int> stockleTodayProvider = Provider<int>(
  (Ref ref) => stockleDayNumber(DateTime.now().toUtc()),
);

/// One day's game, persisted so closing the app mid-puzzle does not lose it —
/// and so a lost puzzle cannot be replayed for a second try at the points.
class StockleController extends Notifier<StockleState?> {
  static const String _dayKey = 'stockle.day';
  static const String _guessesKey = 'stockle.guesses';
  static const String _pointsKey = 'stockle.points_total';
  static const String _playedKey = 'stockle.days_played';
  static const String _wonKey = 'stockle.days_won';
  static const String _streakKey = 'stockle.streak';
  static const String _lastWonDayKey = 'stockle.last_won_day';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  StockleState? build() {
    final AsyncValue<StockleDictionary> dictionary = ref.watch(
      stockleDictionaryProvider,
    );
    final StockleDictionary? dict = dictionary.value;
    if (dict == null) return null;

    final int today = ref.watch(stockleTodayProvider);
    final StockleTicker answer = stockleAnswerFor(
      DateTime.now().toUtc(),
      dict,
    );

    // A stored game from an earlier day is not today's puzzle; start fresh
    // rather than showing yesterday's board.
    if (_prefs.getInt(_dayKey) != today) {
      return StockleState.fresh(answer: answer, dayNumber: today);
    }

    final List<String> played = _prefs.getStringList(_guessesKey) ?? <String>[];
    return StockleState(
      answer: answer,
      dayNumber: today,
      guesses: played
          .map(
            (String symbol) => StockleGuess(
              symbol: symbol,
              marks: scoreGuess(symbol, answer.symbol),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Submits a guess. Returns null on success, or the reason it was refused.
  Future<GuessRejection?> guess(String symbol) async {
    final StockleState? current = state;
    final StockleDictionary? dict = ref.read(stockleDictionaryProvider).value;
    if (current == null || dict == null) return GuessRejection.gameOver;

    final result = current.submit(symbol, dict);
    if (result.rejection != null) return result.rejection;

    final StockleState next = result.state!;
    state = next;

    await _prefs.setInt(_dayKey, next.dayNumber);
    await _prefs.setStringList(
      _guessesKey,
      next.guesses.map((StockleGuess g) => g.symbol).toList(),
    );

    if (next.isOver) await _recordFinish(next);
    return null;
  }

  /// Banks the result once, at the moment the day's game ends.
  ///
  /// Points work like the lesson Q&A: get it right and you earn them. A loss
  /// earns nothing — it never subtracts, because punishing someone for playing
  /// is the sort of thing CLAUDE.md rule 9 rules out.
  Future<void> _recordFinish(StockleState finished) async {
    // Guard against double-banking if the widget rebuilds and resubmits.
    if (_prefs.getInt(_lastWonDayKey) == finished.dayNumber) return;

    await _prefs.setInt(_playedKey, (_prefs.getInt(_playedKey) ?? 0) + 1);

    if (!finished.isWon) {
      // A missed day ends the streak.
      await _prefs.setInt(_streakKey, 0);
      return;
    }

    await _prefs.setInt(_lastWonDayKey, finished.dayNumber);
    await _prefs.setInt(_wonKey, (_prefs.getInt(_wonKey) ?? 0) + 1);
    await _prefs.setInt(
      _pointsKey,
      (_prefs.getInt(_pointsKey) ?? 0) + stocklePoints(finished),
    );

    // Consecutive only if yesterday's puzzle was also solved.
    final int previousWin = _prefs.getInt(_streakKey) ?? 0;
    final int lastWon = _prefs.getInt(_lastWonDayKey) ?? -1;
    final bool consecutive = lastWon == finished.dayNumber - 1;
    await _prefs.setInt(_streakKey, consecutive ? previousWin + 1 : 1);

    ref.invalidate(stockleStatsProvider);
  }
}

final NotifierProvider<StockleController, StockleState?> stockleProvider =
    NotifierProvider<StockleController, StockleState?>(StockleController.new);

/// Lifetime Stockle record.
class StockleStats {
  const StockleStats({
    required this.played,
    required this.won,
    required this.streak,
    required this.points,
  });

  final int played;
  final int won;
  final int streak;
  final int points;

  /// Null rather than zero when nothing has been played, so the UI can say
  /// "no games yet" instead of showing a discouraging 0%.
  int? get winPercent =>
      played == 0 ? null : ((won / played) * 100).round();
}

final Provider<StockleStats> stockleStatsProvider = Provider<StockleStats>((
  Ref ref,
) {
  final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
  return StockleStats(
    played: prefs.getInt(StockleController._playedKey) ?? 0,
    won: prefs.getInt(StockleController._wonKey) ?? 0,
    streak: prefs.getInt(StockleController._streakKey) ?? 0,
    points: prefs.getInt(StockleController._pointsKey) ?? 0,
  );
});

/// Points earned from Stockle, kept separate from lesson points.
///
/// NOT yet part of the Ranks leaderboard. That board is computed server-side
/// from `lesson_progress.points_earned`, a GENERATED column, precisely so a
/// modified client cannot report its own score. Feeding a client-computed
/// number into it would reopen that hole, so Stockle points show in-app only
/// until the server can verify a solve. See DEPLOY.md.
final Provider<int> stocklePointsProvider = Provider<int>(
  (Ref ref) => ref.watch(stockleStatsProvider).points,
);
