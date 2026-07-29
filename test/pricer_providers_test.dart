import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/black_scholes.dart';
import 'package:optionsschool/pricing/payoff.dart';
import 'package:optionsschool/pricing/priced_leg.dart';
import 'package:optionsschool/providers/pricer_providers.dart';

/// The Phase 4 provider layer: does dragging a slider (i.e. calling a
/// controller method) actually flow through to a live re-priced quote and a
/// correctly-composed strategy? This is what a learner's finger movement on
/// the simulator ultimately triggers.
void main() {
  group('market environment', () {
    test('starts from the documented defaults', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final MarketEnvironment env = container.read(marketEnvironmentProvider);
      expect(env.spot, 100);
      expect(env.volatility, 0.25);
      expect(env.timeToExpiry, 0.5);
      expect(env.rate, 0.04);
    });

    test('setSpot updates state and reset() restores the defaults', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(marketEnvironmentProvider.notifier).setSpot(150);
      expect(container.read(marketEnvironmentProvider).spot, 150);

      container.read(marketEnvironmentProvider.notifier).reset();
      expect(container.read(marketEnvironmentProvider).spot, 100);
    });
  });

  group('single option quote', () {
    test('recomputes live when the strike slider moves', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final double atTheMoney = container.read(singleOptionQuoteProvider).price;

      container.read(singleOptionProvider.notifier).setStrike(60);
      final double deepInTheMoney = container.read(singleOptionQuoteProvider).price;

      // A call struck well below spot must be worth more than one at the
      // money — this is the live-repricing path a slider drag exercises.
      expect(deepInTheMoney, greaterThan(atTheMoney));
    });

    test('switching call to put changes the quote to match a fresh BSM call', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(singleOptionProvider.notifier).setType(OptionType.put);
      final MarketEnvironment env = container.read(marketEnvironmentProvider);
      final SingleOptionState option = container.read(singleOptionProvider);

      final BsmQuote expected = bsmQuote(
        OptionType.put,
        BsmInputs(
          spot: env.spot,
          strike: option.strike,
          rate: env.rate,
          volatility: env.volatility,
          timeToExpiry: env.timeToExpiry,
        ),
      );
      expect(container.read(singleOptionQuoteProvider).price, expected.price);
    });

    test('the payoff leg tracks the option type and strike', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(singleOptionProvider.notifier).setType(OptionType.put);
      container.read(singleOptionProvider.notifier).setStrike(80);

      final List<StrategyLeg> legs = container.read(singleOptionLegsProvider);
      expect(legs, hasLength(1));
      expect(legs.single.kind, LegKind.put);
      expect(legs.single.side, LegSide.long);
      expect(legs.single.strike, 80);
    });
  });

  group('strategy presets', () {
    test('each preset builds the leg shape CLAUDE.md Phase 4 asks for', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final StrategyController controller = container.read(strategyProvider.notifier);

      controller.selectPreset(StrategyPreset.bullCallSpread);
      List<StrategyLegSpec> legs = container.read(strategyProvider).legs;
      expect(legs.map((StrategyLegSpec l) => l.kind), <LegKind>[LegKind.call, LegKind.call]);
      expect(legs.map((StrategyLegSpec l) => l.side), <LegSide>[LegSide.long, LegSide.short]);
      expect(legs[1].strike, greaterThan(legs[0].strike));

      controller.selectPreset(StrategyPreset.bearPutSpread);
      legs = container.read(strategyProvider).legs;
      expect(legs.map((StrategyLegSpec l) => l.kind), <LegKind>[LegKind.put, LegKind.put]);
      expect(legs[1].strike, lessThan(legs[0].strike));

      controller.selectPreset(StrategyPreset.straddle);
      legs = container.read(strategyProvider).legs;
      expect(legs.map((StrategyLegSpec l) => l.kind), <LegKind>[LegKind.call, LegKind.put]);
      expect(legs.every((StrategyLegSpec l) => l.side == LegSide.long), isTrue);
      expect(legs[0].strike, legs[1].strike);

      controller.selectPreset(StrategyPreset.coveredCall);
      legs = container.read(strategyProvider).legs;
      expect(legs[0].kind, LegKind.underlying);
      expect(legs[1], predicate<StrategyLegSpec>((StrategyLegSpec l) => l.kind == LegKind.call && l.side == LegSide.short));

      controller.selectPreset(StrategyPreset.protectivePut);
      legs = container.read(strategyProvider).legs;
      expect(legs[0].kind, LegKind.underlying);
      expect(legs[1], predicate<StrategyLegSpec>((StrategyLegSpec l) => l.kind == LegKind.put && l.side == LegSide.long));
    });

    test('legs are priced live off the shared market environment', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(strategyProvider.notifier).selectPreset(StrategyPreset.straddle);

      final double firstPremium = container.read(strategyLegsProvider).first.premium;
      container.read(marketEnvironmentProvider.notifier).setVolatility(0.9);
      final double afterVolSpike = container.read(strategyLegsProvider).first.premium;

      // A straddle's long call gets strictly more valuable as volatility
      // rises — the leg must be repriced, not cached from selection time.
      expect(afterVolSpike, greaterThan(firstPremium));
    });

    test('dragging a leg strike keeps only that leg changed', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final StrategyController controller = container.read(strategyProvider.notifier);
      controller.selectPreset(StrategyPreset.bullCallSpread);

      final double originalShortStrike = container.read(strategyProvider).legs[1].strike;
      controller.setLegStrike(0, 70);

      final List<StrategyLegSpec> legs = container.read(strategyProvider).legs;
      expect(legs[0].strike, 70);
      expect(legs[1].strike, originalShortStrike);
    });

    test('switching preset discards a dragged strike and rebuilds at spot', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final StrategyController controller = container.read(strategyProvider.notifier);
      controller.selectPreset(StrategyPreset.bullCallSpread);
      controller.setLegStrike(0, 30);

      controller.selectPreset(StrategyPreset.straddle);
      final double spot = container.read(marketEnvironmentProvider).spot;
      expect(container.read(strategyProvider).legs[0].strike, spot.roundToDouble());
    });

    test('the covered call caps the loss — no unbounded downside warning', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(strategyProvider.notifier).selectPreset(StrategyPreset.coveredCall);

      final List<StrategyLeg> legs = container.read(strategyLegsProvider);
      expect(hasUnboundedUpsideLoss(legs), isFalse);
    });

    test('none of the built-in presets carry a naked short — all defined-risk', () {
      // Every strategy on offer pairs its short leg with either a further
      // long option (a spread) or the shares themselves (a covered call) —
      // deliberately, per CLAUDE.md rule 2, so nothing in the preset picker
      // needs the unbounded-loss warning banner.
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final StrategyController controller = container.read(strategyProvider.notifier);

      for (final StrategyPreset preset in StrategyPreset.values) {
        controller.selectPreset(preset);
        expect(
          hasUnboundedUpsideLoss(container.read(strategyLegsProvider)),
          isFalse,
          reason: '${preset.label} should not be flagged unbounded',
        );
      }
    });
  });

  group('aggregate Greeks', () {
    test('a covered call has a net delta below the naked shares (the short call sheds some)', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(strategyProvider.notifier).selectPreset(StrategyPreset.coveredCall);

      final AggregateGreeks greeks = container.read(strategyGreeksProvider);
      expect(greeks.delta, greaterThan(0));
      expect(greeks.delta, lessThan(1));
    });

    test('a straddle at the money has the call and put legs mostly offsetting', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(strategyProvider.notifier).selectPreset(StrategyPreset.straddle);

      final AggregateGreeks greeks = container.read(strategyGreeksProvider);
      // The two legs don't cancel exactly — at a positive rate, an
      // at-the-money strike is not quite delta-neutral — but they should
      // offset far more than either leg's own delta (~0.5-0.6 alone).
      expect(greeks.delta.abs(), lessThan(0.3));
      expect(greeks.gamma, greaterThan(0));
      expect(greeks.vega, greaterThan(0));
    });
  });
}
