import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/market.dart';
import 'repository_providers.dart';

/// The symbols this learner follows. Starts at [kDefaultWatchlist] and is
/// theirs to change — searching for a ticker and trading it adds it here.
class WatchlistController extends Notifier<List<String>> {
  static const String _key = 'market_watchlist_v1';

  @override
  List<String> build() {
    final List<String>? saved = ref
        .watch(sharedPreferencesProvider)
        .getStringList(_key);
    return saved == null || saved.isEmpty ? kDefaultWatchlist : saved;
  }

  /// Returns null on success, or why the symbol was not added.
  Future<String?> add(String raw) async {
    final String symbol = raw.trim().toUpperCase();
    if (!isPlausibleSymbol(symbol)) return 'That does not look like a ticker.';
    if (state.contains(symbol)) return null;
    if (state.length >= kMaxWatchlist) {
      return 'You are following $kMaxWatchlist symbols already. Remove one '
          'first.';
    }
    await _write(<String>[symbol, ...state]);
    return null;
  }

  Future<void> remove(String symbol) async {
    await _write(state.where((String s) => s != symbol).toList());
  }

  Future<void> _write(List<String> next) async {
    state = next;
    await ref.read(sharedPreferencesProvider).setStringList(_key, next);
  }
}

final NotifierProvider<WatchlistController, List<String>> watchlistProvider =
    NotifierProvider<WatchlistController, List<String>>(
      WatchlistController.new,
    );

/// Every symbol that needs a price: the watchlist, plus anything held. A
/// position must stay marked to market even if its symbol is dropped from the
/// list, or the portfolio would quietly freeze at its last known value.
final Provider<List<String>> polledSymbolsProvider = Provider<List<String>>((
  Ref ref,
) {
  final Portfolio? p = ref.watch(portfolioControllerProvider).value;
  final Set<String> symbols = <String>{
    ...ref.watch(watchlistProvider),
    if (p != null) ...<String>[
      for (final Holding h in p.holdings) h.symbol,
      for (final OptionHolding o in p.options) o.symbol,
    ],
  };
  return symbols.toList();
});

/// How often the feed is re-read while the Market tab is open.
const Duration kPollInterval = Duration(seconds: 15);

/// Polls the followed symbols on a gentle loop. `autoDispose` so it stops the
/// moment the tab is left — no background polling, no wasted calls.
///
/// Every emission carries the time it was fetched, because the loop cannot be
/// assumed to have been running: the OS suspends timers while the app is in the
/// background, so without a timestamp a price frozen since yesterday looks
/// exactly like one from a moment ago. Invalidating this provider — which is
/// what happens when the app returns to the foreground — restarts the loop and
/// fetches immediately.
final StreamProvider<MarketSnapshot> quotesProvider =
    StreamProvider.autoDispose<MarketSnapshot>((Ref ref) async* {
      final repo = ref.watch(marketRepoProvider);
      final List<String> symbols = ref.watch(polledSymbolsProvider);
      while (true) {
        final List<Quote> quotes = await repo.quotes(symbols);
        yield MarketSnapshot(quotes: quotes, fetchedAt: DateTime.now());
        await Future<void>.delayed(kPollInterval);
      }
    });

/// Symbol search for the Market tab. `autoDispose` and keyed by query so each
/// keystroke's result is cached briefly and dropped when the field clears.
final symbolSearchProvider = FutureProvider.autoDispose
    .family<List<SymbolMatch>, String>((Ref ref, String query) async {
      if (query.trim().isEmpty) return const <SymbolMatch>[];
      return ref.watch(marketRepoProvider).search(query);
    });

/// Latest price per symbol, for marking positions to market.
final Provider<Map<String, double>> pricesProvider =
    Provider.autoDispose<Map<String, double>>((Ref ref) {
      final MarketSnapshot? snapshot = ref.watch(quotesProvider).value;
      return <String, double>{
        for (final Quote q in snapshot?.quotes ?? const <Quote>[])
          q.symbol: q.price,
      };
    });

/// How long a trading week runs before it pays out.
const Duration kSettlementPeriod = Duration(days: 7);

/// Simulated profit needed per point, and the ceiling on one week's award.
const double kDollarsPerPoint = 200;
const int kMaxWeeklyPoints = 300;

/// Points for a week's simulated gain: one per $200, capped.
///
/// A flat or losing week earns zero and never takes points away — market
/// losses must not cost lesson progress (CLAUDE.md rules 2 & 9: encouragement,
/// not a penalty, and never a profit promise; these are points in a game, not
/// money). The cap keeps the market from ever dwarfing the learning, which is
/// what the app is actually for.
int pointsForGain(double gain) {
  if (gain <= 0) return 0;
  return math.min((gain / kDollarsPerPoint).floor(), kMaxWeeklyPoints);
}

/// Where the current trading week stands.
@immutable
class SettlementState {
  const SettlementState({
    required this.weekStarted,
    required this.openingEquity,
    required this.awardedTotal,
  });

  /// When this week began. Null before the first equity reading — the clock
  /// cannot start until there is a value to measure the week against.
  final DateTime? weekStarted;
  final double openingEquity;

  /// Cumulative points from every settled week. This is what the leaderboard
  /// reads, and it only ever goes up.
  final int awardedTotal;

  bool isDue(DateTime now) =>
      weekStarted != null && !now.isBefore(weekStarted!.add(kSettlementPeriod));

  Duration timeRemaining(DateTime now) {
    if (weekStarted == null) return kSettlementPeriod;
    final Duration left = weekStarted!.add(kSettlementPeriod).difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Settles the practice portfolio once a week.
///
/// Points are awarded on what the week actually returned — equity now against
/// equity when the week opened — rather than continuously off an unrealised
/// number that moves every fifteen seconds. That is both honest about what a
/// return is and a far better teacher: it rewards a position that worked out,
/// not a screen that happened to be green when you looked at it.
class MarketBonusController extends Notifier<SettlementState> {
  static const String _pointsKey = 'market_bonus_points_v1';
  static const String _startedKey = 'market_week_started_v1';
  static const String _openingKey = 'market_week_opening_equity_v1';

  @override
  SettlementState build() {
    final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
    final int? startedMs = prefs.getInt(_startedKey);
    return SettlementState(
      weekStarted: startedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(startedMs),
      openingEquity: prefs.getDouble(_openingKey) ?? 0,
      awardedTotal: prefs.getInt(_pointsKey) ?? 0,
    );
  }

  /// Starts the clock, or settles the week if it is up. Returns the points
  /// just awarded, or null if nothing settled.
  ///
  /// Called with the equity currently on screen, so it only ever runs where
  /// there are real prices to value the portfolio with.
  Future<int?> reconcile(double equityNow, DateTime now) async {
    if (state.weekStarted == null) {
      await _write(
        SettlementState(
          weekStarted: now,
          openingEquity: equityNow,
          awardedTotal: state.awardedTotal,
        ),
      );
      return null;
    }

    if (!state.isDue(now)) return null;

    final int earned = pointsForGain(equityNow - state.openingEquity);
    await _write(
      SettlementState(
        weekStarted: now,
        openingEquity: equityNow,
        awardedTotal: state.awardedTotal + earned,
      ),
    );
    return earned;
  }

  /// Back to no history — used when the practice account is reset, so a fresh
  /// account does not settle against a week it never traded.
  Future<void> clear() => _write(
    const SettlementState(
      weekStarted: null,
      openingEquity: 0,
      awardedTotal: 0,
    ),
  );

  Future<void> _write(SettlementState next) async {
    state = next;
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(_pointsKey, next.awardedTotal);
    await prefs.setDouble(_openingKey, next.openingEquity);
    if (next.weekStarted == null) {
      await prefs.remove(_startedKey);
    } else {
      await prefs.setInt(_startedKey, next.weekStarted!.millisecondsSinceEpoch);
    }
  }
}

final NotifierProvider<MarketBonusController, SettlementState>
marketSettlementProvider =
    NotifierProvider<MarketBonusController, SettlementState>(
      MarketBonusController.new,
    );

/// The settled bonus the rest of the app reads — the leaderboard especially.
///
/// It never touches the live feed: no background polling, and no leaked timers
/// in widget tests that pump the board.
final Provider<int> marketBonusPointsProvider = Provider<int>(
  (Ref ref) => ref.watch(marketSettlementProvider).awardedTotal,
);

/// What this week has made so far, and what it would pay if it settled now.
/// Shown on the Market tab so the week in progress is never a mystery.
final Provider<({double gain, int points, Duration left, bool started})>
weekInProgressProvider =
    Provider<({double gain, int points, Duration left, bool started})>((
      Ref ref,
    ) {
      final SettlementState s = ref.watch(marketSettlementProvider);
      final Portfolio? p = ref.watch(portfolioControllerProvider).value;
      final DateTime now = DateTime.now();
      if (p == null || s.weekStarted == null) {
        return (
          gain: 0.0,
          points: 0,
          left: kSettlementPeriod,
          started: false,
        );
      }
      final double gain =
          p.equity(ref.watch(pricesProvider), now) - s.openingEquity;
      return (
        gain: gain,
        points: pointsForGain(gain),
        left: s.timeRemaining(now),
        started: true,
      );
    });

/// True when the prices on screen are the made-up offline walk, so the UI can
/// say "simulated prices" rather than "delayed data" (CLAUDE.md rule 4 & 8).
final Provider<bool> feedIsSyntheticProvider = Provider.autoDispose<bool>((
  Ref ref,
) {
  final List<Quote> quotes =
      ref.watch(quotesProvider).value?.quotes ?? const <Quote>[];
  return quotes.isNotEmpty && quotes.any((Quote q) => q.synthetic);
});

final AsyncNotifierProvider<PortfolioController, Portfolio>
portfolioControllerProvider =
    AsyncNotifierProvider<PortfolioController, Portfolio>(
      PortfolioController.new,
    );

/// The fake-money account. Every trade fills at the last quoted price — an
/// idealised fill with no spread or slippage, which the UI labels as such.
class PortfolioController extends AsyncNotifier<Portfolio> {
  @override
  Future<Portfolio> build() => ref.watch(portfolioRepoProvider).load();

  /// Returns null on success, or a plain-language reason it could not fill.
  Future<String?> buy(String symbol, int shares, double price) async {
    if (shares <= 0) return 'Enter how many shares to buy.';
    final Portfolio? p = state.value;
    if (p == null) return 'The portfolio is still loading.';

    final double cost = shares * price;
    if (cost > p.cash) return 'Not enough simulated cash for that.';

    final Holding? existing = p.holdingFor(symbol);
    final List<Holding> holdings = List<Holding>.of(p.holdings);
    if (existing == null) {
      holdings.add(Holding(symbol: symbol, shares: shares, avgCost: price));
    } else {
      final int total = existing.shares + shares;
      final double avg = (existing.costBasis() + cost) / total;
      holdings[holdings.indexOf(existing)] =
          existing.copyWith(shares: total, avgCost: avg);
    }
    await _persist(p.copyWith(cash: p.cash - cost, holdings: holdings));
    return null;
  }

  Future<String?> sell(String symbol, int shares, double price) async {
    if (shares <= 0) return 'Enter how many shares to sell.';
    final Portfolio? p = state.value;
    if (p == null) return 'The portfolio is still loading.';

    final Holding? existing = p.holdingFor(symbol);
    if (existing == null || existing.shares < shares) {
      return 'You do not own that many shares.';
    }

    final double proceeds = shares * price;
    final int remaining = existing.shares - shares;
    final List<Holding> holdings = List<Holding>.of(p.holdings);
    if (remaining == 0) {
      holdings.removeWhere((Holding h) => h.symbol == symbol);
    } else {
      holdings[holdings.indexOf(existing)] =
          existing.copyWith(shares: remaining);
    }
    await _persist(p.copyWith(cash: p.cash + proceeds, holdings: holdings));
    return null;
  }

  /// The one path every option trade goes through.
  ///
  /// Positions net by contract, and [OptionHolding.contracts] is signed, so the
  /// four cases a learner meets are all the same arithmetic: buying with no
  /// position opens a long, selling into a long closes it, selling past zero
  /// WRITES the option, and buying back a written one closes it. [size] is
  /// always positive — [selling] carries the direction.
  ///
  /// [prices] is the whole watchlist, not just this symbol, because collateral
  /// is checked across every written position at once.
  Future<String?> tradeOption({
    required OptionHolding contract,
    required int size,
    required bool selling,
    required double markPerShare,
    required Map<String, double> prices,
  }) async {
    if (size <= 0) return 'Choose at least one contract.';
    final Portfolio? p = state.value;
    if (p == null) return 'The portfolio is still loading.';

    final OptionHolding? existing = p.optionFor(contract.key);
    final int before = existing?.contracts ?? 0;
    final int delta = selling ? -size : size;
    final int after = before + delta;

    final List<OptionHolding> options = List<OptionHolding>.of(p.options);
    if (after == 0) {
      options.removeWhere((OptionHolding o) => o.key == contract.key);
    } else {
      // The average premium only moves when the position grows in the
      // direction it already had, or flips outright. Trimming a position
      // leaves the basis where it was, so the P/L on what remains is unchanged.
      final double basis;
      if (before == 0 || before.sign != after.sign) {
        basis = markPerShare;
      } else if (delta.sign == before.sign) {
        basis =
            (existing!.premiumPaid * before.abs() + markPerShare * size) /
            after.abs();
      } else {
        basis = existing!.premiumPaid;
      }

      final OptionHolding next = OptionHolding(
        symbol: contract.symbol,
        isCall: contract.isCall,
        strike: contract.strike,
        expiry: contract.expiry,
        contracts: after,
        premiumPaid: basis,
      );
      if (existing == null) {
        options.add(next);
      } else {
        options[options.indexOf(existing)] = next;
      }
    }

    // Selling takes premium in, buying pays it out — including buying back
    // something you wrote, which is where a short position bites.
    final double cashDelta =
        (selling ? 1 : -1) * markPerShare * size * kContractMultiplier;
    final Portfolio candidate = p.copyWith(
      cash: p.cash + cashDelta,
      options: options,
    );

    if (candidate.cash < 0) return 'Not enough simulated cash for that.';

    final DateTime now = DateTime.now();
    if (candidate.buyingPower(prices, now) < 0) {
      final double needed = candidate.marginHeld(prices, now);
      return 'Writing that would tie up ${_money(needed)} of collateral and '
          'you have ${_money(p.cash)} in simulated cash. Write fewer '
          'contracts, or close something first.';
    }

    await _persist(candidate);
    return null;
  }

  /// Back to the starting cash, no positions.
  Future<void> reset() => _persist(const Portfolio.fresh());

  Future<void> _persist(Portfolio next) async {
    state = AsyncData<Portfolio>(next);
    await ref.read(portfolioRepoProvider).save(next);
  }
}

String _money(double v) => '\$${v.toStringAsFixed(2)}';
