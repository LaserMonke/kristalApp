import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/market.dart';
import 'repository_providers.dart';

/// Whether the paid practice market is unlocked.
///
/// Hard-wired ON while the paywall is a separate, later step (DEPLOY.md,
/// "Phase 9b — Paywall"). When that lands, this provider reads the real
/// entitlement instead — and nothing else in the market feature has to change,
/// because everything already gates on it.
final Provider<bool> marketUnlockedProvider = Provider<bool>((Ref ref) => true);

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

/// Polls the followed symbols on a gentle loop. `autoDispose` so it stops the
/// moment the tab is left — no background polling, no wasted calls.
final StreamProvider<List<Quote>> quotesProvider =
    StreamProvider.autoDispose<List<Quote>>((Ref ref) async* {
      final repo = ref.watch(marketRepoProvider);
      final List<String> symbols = ref.watch(polledSymbolsProvider);
      while (true) {
        yield await repo.quotes(symbols);
        await Future<void>.delayed(const Duration(seconds: 15));
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
      final List<Quote> quotes =
          ref.watch(quotesProvider).value ?? const <Quote>[];
      return <String, double>{
        for (final Quote q in quotes) q.symbol: q.price,
      };
    });

/// Extra leaderboard points earned from the practice portfolio's simulated
/// gains: one point per $200 of profit, capped at 300 so the market can never
/// dwarf the learning. A flat or losing portfolio earns zero — market losses
/// never cost lesson points (CLAUDE.md rules 2 & 9: encouragement, not a
/// penalty, and never a profit promise — these are points in a game, not money).
final Provider<int> liveMarketBonusProvider = Provider<int>((Ref ref) {
  final Portfolio? p = ref.watch(portfolioControllerProvider).value;
  if (p == null) return 0;
  final double profit = p.totalReturn(
    ref.watch(pricesProvider),
    DateTime.now(),
  );
  if (profit <= 0) return 0;
  return math.min((profit / 200).floor(), 300);
});

/// The persisted bonus the rest of the app reads — the leaderboard especially.
///
/// It never touches the live feed: no background polling, and no leaked timers
/// in widget tests that pump the board. The Market screen (the one place the
/// feed belongs) keeps it current by mirroring [liveMarketBonusProvider] here.
class MarketBonusController extends Notifier<int> {
  static const String _key = 'market_bonus_points_v1';

  @override
  int build() => ref.watch(sharedPreferencesProvider).getInt(_key) ?? 0;

  Future<void> update(int points) async {
    if (points == state) return;
    state = points;
    await ref.read(sharedPreferencesProvider).setInt(_key, points);
  }
}

final NotifierProvider<MarketBonusController, int> marketBonusPointsProvider =
    NotifierProvider<MarketBonusController, int>(MarketBonusController.new);

/// True when the prices on screen are the made-up offline walk, so the UI can
/// say "simulated prices" rather than "delayed data" (CLAUDE.md rule 4 & 8).
final Provider<bool> feedIsSyntheticProvider = Provider.autoDispose<bool>((
  Ref ref,
) {
  final List<Quote> quotes =
      ref.watch(quotesProvider).value ?? const <Quote>[];
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
