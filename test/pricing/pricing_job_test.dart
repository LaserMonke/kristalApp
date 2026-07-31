import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/barrier.dart';
import 'package:optionsschool/pricing/basket.dart';
import 'package:optionsschool/pricing/black_scholes.dart';
import 'package:optionsschool/pricing/heston.dart';
import 'package:optionsschool/pricing/monte_carlo.dart';
import 'package:optionsschool/pricing/pricing_job.dart';

/// A job has to survive being turned into JSON and back, because that is how
/// it reaches a background isolate and how it would reach the `price-heavy`
/// Edge Function. A field dropped in serialisation would not crash anything —
/// it would silently price a DIFFERENT contract from the one the learner set
/// up, which is the worst kind of bug this app could have.
///
/// So every job type is round-tripped through real `jsonEncode`/`jsonDecode`
/// (not just the map, which would hide type problems) and the price computed
/// from the decoded job is compared with the price computed from the original.
void main() {
  const BsmInputs market = BsmInputs(
    spot: 100,
    strike: 105,
    rate: 0.04,
    volatility: 0.28,
    timeToExpiry: 1.5,
    dividendYield: 0.015,
  );
  const McSettings settings = McSettings(paths: 2000, steps: 20, seed: 1234);

  /// Encodes, decodes and re-encodes. Requiring the two encodings to match
  /// catches a field that is written but never read back.
  PricingJob roundTrip(PricingJob job) {
    final String encoded = jsonEncode(job.toJson());
    final PricingJob decoded = PricingJob.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
    expect(jsonEncode(decoded.toJson()), encoded, reason: job.kind);
    return decoded;
  }

  void expectSamePrice(PricingJob job) {
    final PricingJobResult original = runPricingJob(job);
    final PricingJobResult decoded = runPricingJob(roundTrip(job));

    // Identical, not merely close: the seed is part of the payload, so a
    // faithful round trip must reproduce the run exactly.
    expect(decoded.price, original.price, reason: job.kind);
    expect(decoded.standardError, original.standardError, reason: job.kind);
    expect(decoded.analyticReference, original.analyticReference);
  }

  group('every job survives the round trip', () {
    test('European', () {
      expectSamePrice(
        const EuropeanPricingJob(
          type: OptionType.put,
          inputs: market,
          settings: settings,
        ),
      );
    });

    test('barrier', () {
      expectSamePrice(
        const BarrierPricingJob(
          spec: BarrierSpec(
            type: OptionType.call,
            direction: BarrierDirection.up,
            style: BarrierStyle.knockIn,
            barrier: 130,
          ),
          inputs: market,
          continuityCorrection: true,
          settings: settings,
        ),
      );
    });

    test('Asian', () {
      expectSamePrice(
        const AsianPricingJob(
          type: OptionType.call,
          inputs: market,
          average: AsianAverage.geometric,
          settings: settings,
        ),
      );
    });

    test('basket', () {
      expectSamePrice(
        BasketPricingJob(
          spec: BasketSpec(
            assets: const <BasketAsset>[
              BasketAsset(
                spot: 100,
                volatility: 0.2,
                weight: 0.6,
                dividendYield: 0.01,
                name: 'Asset A',
              ),
              BasketAsset(spot: 90, volatility: 0.35, weight: 0.4),
            ],
            correlation: uniformCorrelation(2, 0.4),
            strike: 95,
            type: OptionType.call,
            rate: 0.03,
            timeToExpiry: 1,
          ),
          settings: const McSettings(paths: 2000, steps: 1, seed: 99),
        ),
      );
    });

    test('Heston', () {
      expectSamePrice(
        const HestonPricingJob(
          type: OptionType.put,
          params: HestonParams.equityLike,
          spot: 100,
          strike: 95,
          rate: 0.03,
          timeToExpiry: 1,
          dividendYield: 0.01,
          payoff: HestonPayoff.asianArithmetic,
          settings: settings,
        ),
      );
    });

    test('the settings themselves survive, seed included', () {
      const BarrierPricingJob job = BarrierPricingJob(
        spec: BarrierSpec(
          type: OptionType.put,
          direction: BarrierDirection.down,
          style: BarrierStyle.knockOut,
          barrier: 70,
        ),
        inputs: market,
        settings: McSettings(
          paths: 3000,
          steps: 33,
          seed: 4242,
          antithetic: false,
        ),
      );
      final PricingJob decoded = roundTrip(job);

      expect(decoded.settings.paths, 3000);
      expect(decoded.settings.steps, 33);
      expect(decoded.settings.seed, 4242);
      expect(decoded.settings.antithetic, isFalse);
    });

    test('every field of a basket asset survives', () {
      final BasketPricingJob job = BasketPricingJob(
        spec: BasketSpec(
          assets: const <BasketAsset>[
            BasketAsset(
              spot: 123.5,
              volatility: 0.31,
              weight: 0.7,
              dividendYield: 0.022,
              name: 'Asset A',
            ),
            BasketAsset(spot: 88, volatility: 0.19, weight: 0.3),
          ],
          correlation: <List<double>>[
            <double>[1, -0.25],
            <double>[-0.25, 1],
          ],
          strike: 110,
          type: OptionType.put,
          rate: 0.025,
          timeToExpiry: 2.5,
          average: BasketAverage.geometric,
        ),
      );
      final BasketPricingJob decoded = roundTrip(job) as BasketPricingJob;

      expect(decoded.spec.assets.first.spot, 123.5);
      expect(decoded.spec.assets.first.dividendYield, 0.022);
      expect(decoded.spec.assets.first.name, 'Asset A');
      expect(decoded.spec.assets.last.volatility, 0.19);
      expect(decoded.spec.correlation[0][1], -0.25);
      expect(decoded.spec.average, BasketAverage.geometric);
      expect(decoded.spec.timeToExpiry, 2.5);
    });
  });

  group('the isolate entry point', () {
    test('takes and returns plain JSON', () {
      const BarrierPricingJob job = BarrierPricingJob(
        spec: BarrierSpec(
          type: OptionType.call,
          direction: BarrierDirection.down,
          style: BarrierStyle.knockOut,
          barrier: 80,
        ),
        inputs: market,
        settings: settings,
      );

      // Through a real string, exactly as it would cross a network.
      final Map<String, dynamic> out = runPricingJobJson(
        jsonDecode(jsonEncode(job.toJson())) as Map<String, dynamic>,
      );
      final PricingJobResult parsed = PricingJobResult.fromJson(
        jsonDecode(jsonEncode(out)) as Map<String, dynamic>,
      );

      expect(parsed.price, runPricingJob(job).price);
      expect(parsed.notes, isNotEmpty);
    });
  });

  group('malformed payloads are refused, not guessed at', () {
    /// The point of being strict. A defaulted field would turn a corrupt
    /// payload into a plausible-looking price — wrong, and confident.
    test('an unknown job kind', () {
      expect(
        () => PricingJob.fromJson(<String, dynamic>{'kind': 'quantum'}),
        throwsA(isA<PricingJobFormatException>()),
      );
    });

    test('an unknown enum value', () {
      expect(
        () => PricingJob.fromJson(<String, dynamic>{
          'kind': 'european',
          'type': 'straddle',
          'inputs': <String, dynamic>{},
          'settings': <String, dynamic>{},
        }),
        throwsA(isA<PricingJobFormatException>()),
      );
    });

    test('a missing number', () {
      expect(
        () => PricingJob.fromJson(<String, dynamic>{
          'kind': 'european',
          'type': 'call',
          'inputs': <String, dynamic>{'spot': 100},
          'settings': <String, dynamic>{
            'paths': 100,
            'steps': 1,
            'seed': 1,
          },
        }),
        throwsA(isA<PricingJobFormatException>()),
      );
    });

    test('a number that is not finite', () {
      expect(
        () => PricingJob.fromJson(<String, dynamic>{
          'kind': 'european',
          'type': 'call',
          'inputs': <String, dynamic>{
            'spot': double.nan,
            'strike': 100,
            'rate': 0.0,
            'volatility': 0.2,
            'time_to_expiry': 1.0,
          },
          'settings': <String, dynamic>{'paths': 100, 'steps': 1, 'seed': 1},
        }),
        throwsA(isA<PricingJobFormatException>()),
      );
    });

    test('a fractional path count', () {
      expect(
        () => PricingJob.fromJson(<String, dynamic>{
          'kind': 'european',
          'type': 'call',
          'inputs': <String, dynamic>{
            'spot': 100.0,
            'strike': 100.0,
            'rate': 0.0,
            'volatility': 0.2,
            'time_to_expiry': 1.0,
          },
          'settings': <String, dynamic>{
            'paths': 100.5,
            'steps': 1,
            'seed': 1,
          },
        }),
        throwsA(isA<PricingJobFormatException>()),
      );
    });

    test('a list where an object belongs', () {
      expect(
        () => PricingJob.fromJson(<String, dynamic>{
          'kind': 'european',
          'type': 'call',
          'inputs': <dynamic>[1, 2, 3],
          'settings': <String, dynamic>{'paths': 1, 'steps': 1, 'seed': 1},
        }),
        throwsA(isA<PricingJobFormatException>()),
      );
    });
  });

  group('results carry an exact answer only where one exists', () {
    test('a European job reports the Black-Scholes price beside it', () {
      const EuropeanPricingJob job = EuropeanPricingJob(
        type: OptionType.call,
        inputs: market,
        settings: McSettings(paths: 40000, steps: 1, seed: 7),
      );
      final PricingJobResult result = runPricingJob(job);

      expect(result.analyticReference, isNotNull);
      expect(
        result.analyticReference,
        closeTo(bsmQuote(OptionType.call, market).price, 1e-12),
      );
      // And the simulation should be sitting on top of it.
      expect(result.referenceDeviationInErrors, lessThan(3));
    });

    test('a barrier job reports the closed form', () {
      const BarrierPricingJob job = BarrierPricingJob(
        spec: BarrierSpec(
          type: OptionType.call,
          direction: BarrierDirection.down,
          style: BarrierStyle.knockOut,
          barrier: 75,
        ),
        inputs: market,
        settings: McSettings(paths: 4000, steps: 20, seed: 8),
      );
      expect(runPricingJob(job).analyticReference, isNotNull);
    });

    test('an arithmetic Asian job reports none, because none exists', () {
      const AsianPricingJob job = AsianPricingJob(
        type: OptionType.call,
        inputs: market,
        settings: settings,
      );
      final PricingJobResult result = runPricingJob(job);

      expect(result.analyticReference, isNull);
      expect(result.referenceDeviationInErrors, isNull);
      expect(
        result.notes.join(' '),
        contains('no closed-form price'),
      );
    });

    test('an arithmetic basket reports none; a geometric one does', () {
      BasketSpec spec(BasketAverage average) => BasketSpec(
        assets: const <BasketAsset>[
          BasketAsset(spot: 100, volatility: 0.2, weight: 0.5),
          BasketAsset(spot: 100, volatility: 0.3, weight: 0.5),
        ],
        correlation: uniformCorrelation(2, 0.3),
        strike: 100,
        type: OptionType.call,
        rate: 0.03,
        timeToExpiry: 1,
        average: average,
      );

      expect(
        runPricingJob(
          BasketPricingJob(spec: spec(BasketAverage.arithmetic)),
        ).analyticReference,
        isNull,
      );
      expect(
        runPricingJob(
          BasketPricingJob(spec: spec(BasketAverage.geometric)),
        ).analyticReference,
        isNotNull,
      );
    });

    test('a Heston European job reports the semi-analytic price; an Asian does not', () {
      const HestonPricingJob european = HestonPricingJob(
        type: OptionType.call,
        params: HestonParams.equityLike,
        spot: 100,
        strike: 100,
        rate: 0.03,
        timeToExpiry: 1,
        settings: McSettings(paths: 2000, steps: 20, seed: 9),
      );
      expect(runPricingJob(european).analyticReference, isNotNull);

      expect(
        runPricingJob(
          const HestonPricingJob(
            type: OptionType.call,
            params: HestonParams.equityLike,
            spot: 100,
            strike: 100,
            rate: 0.03,
            timeToExpiry: 1,
            payoff: HestonPayoff.asianArithmetic,
            settings: McSettings(paths: 2000, steps: 20, seed: 9),
          ),
        ).analyticReference,
        isNull,
      );
    });
  });

  group('notes tell the learner what the number does not', () {
    test('a discretely watched barrier says so', () {
      final PricingJobResult result = runPricingJob(
        const BarrierPricingJob(
          spec: BarrierSpec(
            type: OptionType.call,
            direction: BarrierDirection.down,
            style: BarrierStyle.knockOut,
            barrier: 80,
          ),
          inputs: market,
          settings: McSettings(paths: 1000, steps: 12, seed: 3),
        ),
      );
      expect(result.notes.join(' '), contains('watched at 12 dates'));
      expect(result.notes.join(' '), contains('not continuously'));
    });

    test('an already-breached barrier says nothing was simulated', () {
      final PricingJobResult result = runPricingJob(
        const BarrierPricingJob(
          spec: BarrierSpec(
            type: OptionType.call,
            direction: BarrierDirection.down,
            style: BarrierStyle.knockOut,
            barrier: 120,
          ),
          inputs: market,
          settings: McSettings(paths: 1000, steps: 12, seed: 3),
        ),
      );
      expect(result.price, 0);
      expect(result.standardError, 0);
      expect(result.notes.join(' '), contains('already past the barrier'));
    });

    test('Heston always names its discretisation bias', () {
      final PricingJobResult result = runPricingJob(
        const HestonPricingJob(
          type: OptionType.call,
          params: HestonParams.equityLike,
          spot: 100,
          strike: 100,
          rate: 0.03,
          timeToExpiry: 1,
          settings: McSettings(paths: 1000, steps: 20, seed: 4),
        ),
      );
      expect(result.notes.join(' '), contains('discretisation bias'));
      // The equity-like default violates Feller, so that warning appears too.
      expect(result.notes.join(' '), contains('Feller'));
    });

    test('a basket warns that correlation is the shakiest input', () {
      final PricingJobResult result = runPricingJob(
        BasketPricingJob(
          spec: BasketSpec(
            assets: const <BasketAsset>[
              BasketAsset(spot: 100, volatility: 0.2, weight: 1),
              BasketAsset(spot: 100, volatility: 0.2, weight: 1),
            ],
            correlation: uniformCorrelation(2, 0.5),
            strike: 100,
            type: OptionType.call,
            rate: 0.03,
            timeToExpiry: 1,
          ),
          settings: const McSettings(paths: 1000, steps: 1, seed: 5),
        ),
      );
      expect(result.notes.join(' '), contains('towards 1 in a crash'));
    });
  });

  group('workload', () {
    test('is paths times steps', () {
      const AsianPricingJob job = AsianPricingJob(
        type: OptionType.call,
        inputs: market,
        settings: McSettings(paths: 5000, steps: 60, seed: 1),
      );
      expect(job.workload, 300000);
    });

    test('every job has a label a person can read', () {
      final List<PricingJob> jobs = <PricingJob>[
        const EuropeanPricingJob(type: OptionType.call, inputs: market),
        const BarrierPricingJob(
          spec: BarrierSpec(
            type: OptionType.put,
            direction: BarrierDirection.up,
            style: BarrierStyle.knockIn,
            barrier: 140,
          ),
          inputs: market,
        ),
        const AsianPricingJob(type: OptionType.call, inputs: market),
        BasketPricingJob(
          spec: BasketSpec(
            assets: const <BasketAsset>[
              BasketAsset(spot: 100, volatility: 0.2, weight: 1),
            ],
            correlation: uniformCorrelation(1, 0),
            strike: 100,
            type: OptionType.call,
            rate: 0.03,
            timeToExpiry: 1,
          ),
        ),
        const HestonPricingJob(
          type: OptionType.call,
          params: HestonParams.equityLike,
          spot: 100,
          strike: 100,
          rate: 0.03,
          timeToExpiry: 1,
        ),
      ];

      for (final PricingJob job in jobs) {
        expect(job.label, isNotEmpty, reason: job.kind);
        expect(job.label.length, greaterThan(8), reason: job.kind);
      }
    });
  });
}
