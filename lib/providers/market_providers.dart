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

/// Polls the watchlist on a gentle loop. `autoDispose` so it stops the moment
/// the tab is left — no background polling, no wasted calls.
final StreamProvider<List<Quote>> quotesProvider =
    StreamProvider.autoDispose<List<Quote>>((Ref ref) async* {
      final repo = ref.watch(marketRepoProvider);
      while (true) {
        yield await repo.quotes(kWatchlist);
        await Future<void>.delayed(const Duration(seconds: 15));
      }
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

  /// Opens (or adds to) an option position. [spec] carries the contract terms,
  /// the number of contracts, and the premium per share paid at the mark.
  Future<String?> buyOption(OptionHolding spec) async {
    if (spec.contracts <= 0) return 'Choose at least one contract.';
    final Portfolio? p = state.value;
    if (p == null) return 'The portfolio is still loading.';

    final double cost = spec.costBasis();
    if (cost > p.cash) return 'Not enough simulated cash for that.';

    final OptionHolding? existing = p.optionFor(spec.key);
    final List<OptionHolding> options = List<OptionHolding>.of(p.options);
    if (existing == null) {
      options.add(spec);
    } else {
      final int total = existing.contracts + spec.contracts;
      final double avg =
          (existing.costBasis() + cost) / (total * kContractMultiplier);
      options[options.indexOf(existing)] =
          existing.copyWith(contracts: total, premiumPaid: avg);
    }
    await _persist(p.copyWith(cash: p.cash - cost, options: options));
    return null;
  }

  /// Closes some or all of an option position at [markPerShare].
  Future<String?> sellOption(
    String key,
    int contracts,
    double markPerShare,
  ) async {
    if (contracts <= 0) return 'Choose at least one contract.';
    final Portfolio? p = state.value;
    if (p == null) return 'The portfolio is still loading.';

    final OptionHolding? existing = p.optionFor(key);
    if (existing == null || existing.contracts < contracts) {
      return 'You do not hold that many contracts.';
    }

    final double proceeds = markPerShare * contracts * kContractMultiplier;
    final int remaining = existing.contracts - contracts;
    final List<OptionHolding> options = List<OptionHolding>.of(p.options);
    if (remaining == 0) {
      options.removeWhere((OptionHolding o) => o.key == key);
    } else {
      options[options.indexOf(existing)] =
          existing.copyWith(contracts: remaining);
    }
    await _persist(p.copyWith(cash: p.cash + proceeds, options: options));
    return null;
  }

  /// Back to the starting cash, no positions.
  Future<void> reset() => _persist(const Portfolio.fresh());

  Future<void> _persist(Portfolio next) async {
    state = AsyncData<Portfolio>(next);
    await ref.read(portfolioRepoProvider).save(next);
  }
}
