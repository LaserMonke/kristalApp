import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pricing/black_scholes.dart';
import '../pricing/payoff.dart';
import '../pricing/priced_leg.dart';

// State for the Phase 4 interactive pricer: one shared market environment
// (spot, volatility, time, rate) driving both the single-option view and
// the strategy view, so moving a slider in one place is felt everywhere.

/// Market inputs shared by both pricer tabs — Phase 4's sliders for spot,
/// volatility, time to expiry and rate. Strike lives with each option
/// instead, since a strategy has one strike per leg.
class MarketEnvironmentController extends Notifier<MarketEnvironment> {
  @override
  MarketEnvironment build() => const MarketEnvironment(
    spot: 100,
    volatility: 0.25,
    timeToExpiry: 0.5,
    rate: 0.04,
  );

  void setSpot(double v) => state = state.copyWith(spot: v);
  void setVolatility(double v) => state = state.copyWith(volatility: v);
  void setTimeToExpiry(double v) => state = state.copyWith(timeToExpiry: v);
  void setRate(double v) => state = state.copyWith(rate: v);

  void reset() => state = build();
}

final NotifierProvider<MarketEnvironmentController, MarketEnvironment>
marketEnvironmentProvider =
    NotifierProvider<MarketEnvironmentController, MarketEnvironment>(
      MarketEnvironmentController.new,
    );

/// ── Single option ────────────────────────────────────────────────────────

class SingleOptionState {
  const SingleOptionState({required this.type, required this.strike});

  final OptionType type;
  final double strike;

  SingleOptionState copyWith({OptionType? type, double? strike}) =>
      SingleOptionState(
        type: type ?? this.type,
        strike: strike ?? this.strike,
      );
}

class SingleOptionController extends Notifier<SingleOptionState> {
  @override
  SingleOptionState build() =>
      const SingleOptionState(type: OptionType.call, strike: 100);

  void setType(OptionType type) => state = state.copyWith(type: type);
  void setStrike(double strike) => state = state.copyWith(strike: strike);
}

final NotifierProvider<SingleOptionController, SingleOptionState>
singleOptionProvider =
    NotifierProvider<SingleOptionController, SingleOptionState>(
      SingleOptionController.new,
    );

/// Live price and Greeks for the option on the "Single option" tab, recomputed
/// on every slider tick from the shared market environment.
final Provider<BsmQuote> singleOptionQuoteProvider = Provider<BsmQuote>((
  Ref ref,
) {
  final MarketEnvironment env = ref.watch(marketEnvironmentProvider);
  final SingleOptionState option = ref.watch(singleOptionProvider);
  return bsmQuote(
    option.type,
    BsmInputs(
      spot: env.spot,
      strike: option.strike,
      rate: env.rate,
      volatility: env.volatility,
      timeToExpiry: env.timeToExpiry,
    ),
  );
});

/// The single option as one long leg, priced at its own theoretical premium
/// — feeds the reusable [PayoffDiagram] so the learner sees what buying it
/// today at the model price would be worth at expiry.
final Provider<List<StrategyLeg>> singleOptionLegsProvider =
    Provider<List<StrategyLeg>>((Ref ref) {
      final MarketEnvironment env = ref.watch(marketEnvironmentProvider);
      final SingleOptionState option = ref.watch(singleOptionProvider);
      // Price the ENTRY premium at-the-money (spot = strike), not at the live
      // spot. If it re-priced with the Spot slider, the premium would rise in
      // lock-step with the underlying and the position would sit forever at
      // its own break-even — the marker could never cross into profit. Fixing
      // it turns the Spot slider into "where the underlying finishes", so the
      // learner can drag it past break-even and watch the payoff go green.
      final MarketEnvironment entry = env.copyWith(spot: option.strike);
      return <StrategyLeg>[
        pricedLeg(
          entry,
          kind: option.type == OptionType.call ? LegKind.call : LegKind.put,
          side: LegSide.long,
          strike: option.strike,
        ),
      ];
    });

/// ── Strategy ─────────────────────────────────────────────────────────────

/// A leg's kind, side and strike, without a premium — the premium is priced
/// live from the shared [MarketEnvironment] rather than stored, so it never
/// goes stale when a slider moves.
class StrategyLegSpec {
  const StrategyLegSpec({
    required this.kind,
    required this.side,
    required this.strike,
  });

  final LegKind kind;
  final LegSide side;

  /// Unused (0) for an underlying/share leg.
  final double strike;

  StrategyLegSpec copyWith({double? strike}) =>
      StrategyLegSpec(kind: kind, side: side, strike: strike ?? this.strike);
}

/// A named, pre-built strategy — CLAUDE.md Phase 4 asks for "spreads,
/// straddle, covered call, protective put".
enum StrategyPreset { bullCallSpread, bearPutSpread, straddle, coveredCall, protectivePut }

extension StrategyPresetInfo on StrategyPreset {
  String get label => switch (this) {
    StrategyPreset.bullCallSpread => 'Bull call spread',
    StrategyPreset.bearPutSpread => 'Bear put spread',
    StrategyPreset.straddle => 'Straddle',
    StrategyPreset.coveredCall => 'Covered call',
    StrategyPreset.protectivePut => 'Protective put',
  };

  String get blurb => switch (this) {
    StrategyPreset.bullCallSpread =>
      'Buy a call, sell a further call above it. Caps both the cost and '
          'the upside — a cheaper, lower-conviction bet than a lone call.',
    StrategyPreset.bearPutSpread =>
      'Buy a put, sell a further put below it. Profits if the underlying '
          'falls, with both the risk and the reward capped.',
    StrategyPreset.straddle =>
      'Buy a call and a put at the same strike. Pays off on a big move '
          'either way, and loses if the price just sits still.',
    StrategyPreset.coveredCall =>
      'Own the shares, sell a call above the price. Trades away some '
          'upside for premium income collected today.',
    StrategyPreset.protectivePut =>
      'Own the shares, buy a put below the price. Insurance against a '
          'large drop, paid for with the put premium.',
  };

  /// This strategy's legs, struck relative to [spot] and rounded to whole
  /// numbers so the sliders start on tidy values.
  List<StrategyLegSpec> legsAt(double spot) {
    final double atMoney = spot.roundToDouble();
    final double above = (spot * 1.1).roundToDouble();
    final double below = (spot * 0.9).roundToDouble();

    return switch (this) {
      StrategyPreset.bullCallSpread => <StrategyLegSpec>[
        StrategyLegSpec(kind: LegKind.call, side: LegSide.long, strike: atMoney),
        StrategyLegSpec(kind: LegKind.call, side: LegSide.short, strike: above),
      ],
      StrategyPreset.bearPutSpread => <StrategyLegSpec>[
        StrategyLegSpec(kind: LegKind.put, side: LegSide.long, strike: atMoney),
        StrategyLegSpec(kind: LegKind.put, side: LegSide.short, strike: below),
      ],
      StrategyPreset.straddle => <StrategyLegSpec>[
        StrategyLegSpec(kind: LegKind.call, side: LegSide.long, strike: atMoney),
        StrategyLegSpec(kind: LegKind.put, side: LegSide.long, strike: atMoney),
      ],
      StrategyPreset.coveredCall => <StrategyLegSpec>[
        const StrategyLegSpec(kind: LegKind.underlying, side: LegSide.long, strike: 0),
        StrategyLegSpec(kind: LegKind.call, side: LegSide.short, strike: above),
      ],
      StrategyPreset.protectivePut => <StrategyLegSpec>[
        const StrategyLegSpec(kind: LegKind.underlying, side: LegSide.long, strike: 0),
        StrategyLegSpec(kind: LegKind.put, side: LegSide.long, strike: below),
      ],
    };
  }
}

class StrategyState {
  const StrategyState({required this.preset, required this.legs});

  final StrategyPreset preset;
  final List<StrategyLegSpec> legs;

  StrategyState copyWith({StrategyPreset? preset, List<StrategyLegSpec>? legs}) =>
      StrategyState(preset: preset ?? this.preset, legs: legs ?? this.legs);
}

class StrategyController extends Notifier<StrategyState> {
  @override
  StrategyState build() {
    const StrategyPreset preset = StrategyPreset.bullCallSpread;
    final double spot = ref.read(marketEnvironmentProvider).spot;
    return StrategyState(preset: preset, legs: preset.legsAt(spot));
  }

  /// Swapping the preset rebuilds the legs from scratch at the current spot
  /// — any strike the learner had dragged on the old preset is discarded,
  /// since it belonged to a different strategy shape.
  void selectPreset(StrategyPreset preset) {
    final double spot = ref.read(marketEnvironmentProvider).spot;
    state = StrategyState(preset: preset, legs: preset.legsAt(spot));
  }

  void setLegStrike(int index, double strike) {
    final List<StrategyLegSpec> legs = <StrategyLegSpec>[...state.legs];
    legs[index] = legs[index].copyWith(strike: strike);
    state = state.copyWith(legs: legs);
  }
}

final NotifierProvider<StrategyController, StrategyState> strategyProvider =
    NotifierProvider<StrategyController, StrategyState>(StrategyController.new);

/// The strategy's legs, priced live under the shared market environment.
final Provider<List<StrategyLeg>> strategyLegsProvider =
    Provider<List<StrategyLeg>>((Ref ref) {
      final MarketEnvironment env = ref.watch(marketEnvironmentProvider);
      final StrategyState strategy = ref.watch(strategyProvider);
      return <StrategyLeg>[
        for (final StrategyLegSpec spec in strategy.legs)
          pricedLeg(env, kind: spec.kind, side: spec.side, strike: spec.strike),
      ];
    });

/// Portfolio Greeks: each leg's Greeks, signed for long/short and summed.
/// A share leg has a delta of exactly 1 (or -1 short) and no gamma, vega,
/// theta or rho under this model — its value moves one-for-one with the
/// underlying and nothing else.
class AggregateGreeks {
  const AggregateGreeks({
    required this.delta,
    required this.gamma,
    required this.vega,
    required this.theta,
    required this.rho,
  });

  final double delta;
  final double gamma;
  final double vega;
  final double theta;
  final double rho;
}

final Provider<AggregateGreeks> strategyGreeksProvider =
    Provider<AggregateGreeks>((Ref ref) {
      final MarketEnvironment env = ref.watch(marketEnvironmentProvider);
      final StrategyState strategy = ref.watch(strategyProvider);

      double delta = 0, gamma = 0, vega = 0, theta = 0, rho = 0;
      for (final StrategyLegSpec spec in strategy.legs) {
        final double sign = spec.side == LegSide.long ? 1 : -1;
        if (spec.kind == LegKind.underlying) {
          delta += sign;
          continue;
        }
        final BsmQuote q = bsmQuote(
          spec.kind == LegKind.call ? OptionType.call : OptionType.put,
          BsmInputs(
            spot: env.spot,
            strike: spec.strike,
            rate: env.rate,
            volatility: env.volatility,
            timeToExpiry: env.timeToExpiry,
          ),
        );
        delta += sign * q.delta;
        gamma += sign * q.gamma;
        vega += sign * q.vega;
        theta += sign * q.theta;
        rho += sign * q.rho;
      }
      return AggregateGreeks(delta: delta, gamma: gamma, vega: vega, theta: theta, rho: rho);
    });
