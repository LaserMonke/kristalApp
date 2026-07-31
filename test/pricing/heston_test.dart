import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/black_scholes.dart';
import 'package:optionsschool/pricing/heston.dart';
import 'package:optionsschool/pricing/monte_carlo.dart';

/// Heston is checked four ways, because no single check would be convincing:
///
///   1. Against reference prices computed independently in Python, using
///      Python's native complex arithmetic and a 200,000-point Simpson rule
///      — so neither the complex type nor the Gauss-Legendre quadrature in
///      this package is shared with the reference.
///   2. Against BLACK-SCHOLES in the limit where Heston must become it: send
///      the vol-of-vol to zero with variance already at its long-run level
///      and the second source of randomness disappears. This one is the real
///      test of the formula itself, since it involves no shared derivation.
///   3. Against PUT-CALL PARITY, which no model may break.
///   4. Against the Monte Carlo engine, which shares none of the Fourier
///      machinery — agreement between a formula and a simulation that have
///      almost no code in common is strong evidence for both.
void main() {
  const HestonParams caseA = HestonParams(
    initialVariance: 0.04,
    longRunVariance: 0.04,
    meanReversion: 1.5,
    volOfVol: 0.3,
    correlation: -0.5,
  );

  group('semi-analytic prices vs independent reference values', () {
    test('case A: v0=theta=0.04, kappa=1.5, xi=0.3, rho=-0.5, T=1', () {
      double call(double strike) => hestonVanillaPrice(
        OptionType.call,
        params: caseA,
        spot: 100,
        strike: strike,
        rate: 0.02,
        timeToExpiry: 1,
      );
      double put(double strike) => hestonVanillaPrice(
        OptionType.put,
        params: caseA,
        spot: 100,
        strike: strike,
        rate: 0.02,
        timeToExpiry: 1,
      );

      expect(call(90), closeTo(15.0070958063, 1e-6));
      expect(call(100), closeTo(8.6459834137, 1e-6));
      expect(call(110), closeTo(4.2719198298, 1e-6));
      expect(put(90), closeTo(3.2249764039, 1e-6));
      expect(put(100), closeTo(6.6658507444, 1e-6));
      expect(put(110), closeTo(12.0937738936, 1e-6));
    });

    test('case B: equity-like skew with a dividend yield, T=0.5', () {
      double call(double strike) => hestonVanillaPrice(
        OptionType.call,
        params: HestonParams.equityLike,
        spot: 100,
        strike: strike,
        rate: 0.03,
        timeToExpiry: 0.5,
        dividendYield: 0.01,
      );

      expect(call(80), closeTo(21.8721277124, 1e-6));
      expect(call(100), closeTo(7.1456535737, 1e-6));
      expect(call(120), closeTo(0.7517704528, 1e-6));
    });

    /// The case that catches a wrong branch of the complex logarithm. Heston's
    /// original 1993 formulation prices this visibly wrong while remaining
    /// correct at short maturities, which is exactly how the bug hides. If
    /// this test starts failing while the one-year cases still pass, the
    /// characteristic function has drifted off the principal branch.
    test('case C: five years, where the branch cut would bite', () {
      const HestonParams longDated = HestonParams(
        initialVariance: 0.04,
        longRunVariance: 0.09,
        meanReversion: 1.0,
        volOfVol: 0.6,
        correlation: -0.3,
      );

      expect(
        hestonVanillaPrice(
          OptionType.call,
          params: longDated,
          spot: 100,
          strike: 100,
          rate: 0.03,
          timeToExpiry: 5,
        ),
        closeTo(29.1531237909, 1e-5),
      );
    });
  });

  group('collapses to Black-Scholes when it should', () {
    /// With variance starting AT its long-run level and almost no vol-of-vol,
    /// there is nothing left for the variance process to do: it sits still,
    /// and Heston becomes Black-Scholes with a constant volatility of
    /// sqrt(theta). This check shares no derivation with the reference values
    /// above, so it tests the formula rather than the transcription.
    ///
    /// Run AT [HestonParams.minimumUsableVolOfVol] rather than at something
    /// nearer zero, because the characteristic function is ill-conditioned
    /// there — see the next test, which pins that behaviour down so it cannot
    /// be mistaken for a pricing bug later.
    test('vol-of-vol near zero reproduces Black-Scholes', () {
      const double variance = 0.0625; // a 25% volatility
      const HestonParams degenerate = HestonParams(
        initialVariance: variance,
        longRunVariance: variance,
        meanReversion: 1.0,
        volOfVol: HestonParams.minimumUsableVolOfVol,
        correlation: 0,
      );

      for (final double strike in <double>[80, 90, 100, 110, 125]) {
        for (final OptionType type in OptionType.values) {
          final double heston = hestonVanillaPrice(
            type,
            params: degenerate,
            spot: 100,
            strike: strike,
            rate: 0.04,
            timeToExpiry: 1,
            dividendYield: 0.015,
          );
          final double blackScholes = bsmQuote(
            type,
            BsmInputs(
              spot: 100,
              strike: strike,
              rate: 0.04,
              volatility: math.sqrt(variance),
              timeToExpiry: 1,
              dividendYield: 0.015,
            ),
          ).price;

          expect(
            heston,
            closeTo(blackScholes, 1e-3),
            reason: '$type strike=$strike',
          );
        }
      }
    });

    /// Pins down the ill-conditioning itself, so that a future reader finding
    /// a wrong price at a tiny vol-of-vol recognises a known numerical limit
    /// rather than hunting a bug in the characteristic function.
    ///
    /// The error is U-shaped in xi: dominated by floating-point cancellation
    /// below [HestonParams.minimumUsableVolOfVol] (the `kappa*theta/xi^2`
    /// factor grows without bound), and by the genuine difference between the
    /// two models above it.
    test('below the usable vol-of-vol floor, accuracy degrades — as documented', () {
      const double variance = 0.0625;
      double worstErrorAt(double xi) {
        final HestonParams params = HestonParams(
          initialVariance: variance,
          longRunVariance: variance,
          meanReversion: 1.0,
          volOfVol: xi,
          correlation: 0,
        );
        double worst = 0;
        for (final double strike in <double>[80, 100, 125]) {
          final double heston = hestonVanillaPrice(
            OptionType.call,
            params: params,
            spot: 100,
            strike: strike,
            rate: 0.04,
            timeToExpiry: 1,
          );
          final double exact = bsmQuote(
            OptionType.call,
            BsmInputs(
              spot: 100,
              strike: strike,
              rate: 0.04,
              volatility: math.sqrt(variance),
              timeToExpiry: 1,
            ),
          ).price;
          worst = math.max(worst, (heston - exact).abs());
        }
        return worst;
      }

      // Accurate at the documented floor...
      expect(worstErrorAt(HestonParams.minimumUsableVolOfVol), lessThan(1e-3));
      // ...and progressively worse below it, which is the numerical artefact
      // the floor exists to keep the app away from.
      expect(worstErrorAt(1e-3), greaterThan(worstErrorAt(1e-2)));
      expect(worstErrorAt(1e-5), greaterThan(1.0));
    });
  });

  group('put-call parity', () {
    test('holds across strikes, maturities and correlations', () {
      for (final double strike in <double>[70, 100, 130]) {
        for (final double t in <double>[0.25, 1, 3]) {
          for (final double rho in <double>[-0.8, 0, 0.5]) {
            final HestonParams params = caseA.copyWith(correlation: rho);
            const double spot = 100;
            const double rate = 0.03;
            const double q = 0.01;

            final double call = hestonVanillaPrice(
              OptionType.call,
              params: params,
              spot: spot,
              strike: strike,
              rate: rate,
              timeToExpiry: t,
              dividendYield: q,
            );
            final double put = hestonVanillaPrice(
              OptionType.put,
              params: params,
              spot: spot,
              strike: strike,
              rate: rate,
              timeToExpiry: t,
              dividendYield: q,
            );

            expect(
              call - put,
              closeTo(
                spot * math.exp(-q * t) - strike * math.exp(-rate * t),
                1e-8,
              ),
              reason: 'strike=$strike T=$t rho=$rho',
            );
          }
        }
      }
    });
  });

  group('the smile is the point of the model', () {
    /// Black-Scholes would draw a flat line here — it has only one volatility
    /// to give. Heston does not, and that difference is the entire reason the
    /// model exists.
    test('implied volatility is not constant across strikes', () {
      final List<SmilePoint> smile = hestonSmile(
        params: HestonParams.equityLike,
        spot: 100,
        rate: 0.03,
        timeToExpiry: 1,
      );

      final List<double> vols = <double>[
        for (final SmilePoint p in smile)
          if (p.impliedVolatility != null) p.impliedVolatility!,
      ];

      expect(vols.length, greaterThan(15));
      final double lowest = vols.reduce(math.min);
      final double highest = vols.reduce(math.max);
      expect(highest - lowest, greaterThan(0.02));
    });

    /// The leverage effect. A negative correlation means prices fall as
    /// volatility rises, which fattens the left tail: low strikes (crash
    /// protection) carry a HIGHER implied volatility than high ones. This
    /// downward slope is what equity option markets actually show, and
    /// reproducing it is Heston's main claim on a learner's attention.
    test('negative correlation tilts the smile into a downward skew', () {
      final List<SmilePoint> skewed = hestonSmile(
        params: HestonParams.equityLike.copyWith(correlation: -0.7),
        spot: 100,
        rate: 0.03,
        timeToExpiry: 1,
        strikes: 9,
      );

      final double? low = skewed.first.impliedVolatility;
      final double? high = skewed.last.impliedVolatility;
      expect(low, isNotNull);
      expect(high, isNotNull);
      expect(low!, greaterThan(high!));
    });

    test('positive correlation tilts it the other way', () {
      final List<SmilePoint> reversed = hestonSmile(
        params: HestonParams.equityLike.copyWith(correlation: 0.7),
        spot: 100,
        rate: 0.03,
        timeToExpiry: 1,
        strikes: 9,
      );

      expect(
        reversed.first.impliedVolatility!,
        lessThan(reversed.last.impliedVolatility!),
      );
    });

    test('zero correlation leaves a symmetric smile, not a flat line', () {
      final List<SmilePoint> symmetric = hestonSmile(
        params: HestonParams.equityLike.copyWith(correlation: 0),
        spot: 100,
        rate: 0.03,
        timeToExpiry: 1,
        strikes: 11,
      );

      final double? atTheMoney = symmetric[5].impliedVolatility;
      // The wings sit above the middle: a smile, which is what vol-of-vol
      // alone produces once the skew from correlation is switched off.
      expect(symmetric.first.impliedVolatility!, greaterThan(atTheMoney!));
      expect(symmetric.last.impliedVolatility!, greaterThan(atTheMoney));
    });
  });

  group('implied volatility solver', () {
    test('inverts Black-Scholes back to the volatility it was given', () {
      for (final double vol in <double>[0.08, 0.2, 0.45, 0.9]) {
        for (final double strike in <double>[85, 100, 120]) {
          final double price = bsmQuote(
            OptionType.call,
            BsmInputs(
              spot: 100,
              strike: strike,
              rate: 0.03,
              volatility: vol,
              timeToExpiry: 0.75,
            ),
          ).price;

          expect(
            impliedVolatility(
              OptionType.call,
              price: price,
              spot: 100,
              strike: strike,
              rate: 0.03,
              timeToExpiry: 0.75,
            ),
            closeTo(vol, 1e-5),
            reason: 'vol=$vol strike=$strike',
          );
        }
      }
    });

    test('returns null rather than inventing a number', () {
      // A price of zero, and a price above the underlying itself, are both
      // outside what any volatility can produce.
      expect(
        impliedVolatility(
          OptionType.call,
          price: 0,
          spot: 100,
          strike: 100,
          rate: 0.03,
          timeToExpiry: 1,
        ),
        isNull,
      );
      expect(
        impliedVolatility(
          OptionType.call,
          price: 150,
          spot: 100,
          strike: 100,
          rate: 0.03,
          timeToExpiry: 1,
        ),
        isNull,
      );
    });
  });

  group('simulation agrees with the formula', () {
    /// The simulation shares no code with the Fourier pricer — different
    /// mathematics, different failure modes. Where they agree, both are
    /// probably right.
    ///
    /// Full-truncation Euler carries a discretisation bias on TOP of its
    /// sampling error, and that bias is not described by the standard error,
    /// so the tolerance allows for it explicitly rather than pretending the
    /// error bar covers everything.
    test('at the money', () {
      final double exact = hestonVanillaPrice(
        OptionType.call,
        params: caseA,
        spot: 100,
        strike: 100,
        rate: 0.02,
        timeToExpiry: 1,
      );
      final McEstimate mc = hestonMonteCarloPrice(
        OptionType.call,
        params: caseA,
        spot: 100,
        strike: 100,
        rate: 0.02,
        timeToExpiry: 1,
        settings: const McSettings(paths: 60000, steps: 250, seed: 61),
      );

      expect((mc.price - exact).abs(), lessThan(3 * mc.standardError + 0.05));
    });

    test('out of the money, and for a put', () {
      final double exactCall = hestonVanillaPrice(
        OptionType.call,
        params: caseA,
        spot: 100,
        strike: 120,
        rate: 0.02,
        timeToExpiry: 1,
      );
      final McEstimate mcCall = hestonMonteCarloPrice(
        OptionType.call,
        params: caseA,
        spot: 100,
        strike: 120,
        rate: 0.02,
        timeToExpiry: 1,
        settings: const McSettings(paths: 60000, steps: 250, seed: 62),
      );
      expect(
        (mcCall.price - exactCall).abs(),
        lessThan(3 * mcCall.standardError + 0.05),
      );

      final double exactPut = hestonVanillaPrice(
        OptionType.put,
        params: caseA,
        spot: 100,
        strike: 90,
        rate: 0.02,
        timeToExpiry: 1,
      );
      final McEstimate mcPut = hestonMonteCarloPrice(
        OptionType.put,
        params: caseA,
        spot: 100,
        strike: 90,
        rate: 0.02,
        timeToExpiry: 1,
        settings: const McSettings(paths: 60000, steps: 250, seed: 63),
      );
      expect(
        (mcPut.price - exactPut).abs(),
        lessThan(3 * mcPut.standardError + 0.05),
      );
    });

    /// The discretisation bias is real and worth seeing, because it is the
    /// one error a standard error does NOT describe: a coarse Euler run can
    /// report a tight confidence interval around the wrong number.
    ///
    /// Note that a shared seed does NOT give common random numbers across
    /// different step counts here — the runs consume different numbers of
    /// shocks, so their sampling errors are independent. The step counts are
    /// therefore chosen far enough apart that the bias gap dwarfs the noise:
    /// at two steps the error is around 0.27 against a standard error near
    /// 0.03, and at two hundred it is within the noise.
    test('a coarse Euler run is biased, and more steps remove it', () {
      final double exact = hestonVanillaPrice(
        OptionType.call,
        params: caseA,
        spot: 100,
        strike: 100,
        rate: 0.02,
        timeToExpiry: 1,
      );
      ({double bias, double standardError}) runWith(int steps) {
        final McEstimate mc = hestonMonteCarloPrice(
          OptionType.call,
          params: caseA,
          spot: 100,
          strike: 100,
          rate: 0.02,
          timeToExpiry: 1,
          settings: McSettings(paths: 60000, steps: steps, seed: 64),
        );
        return (bias: (mc.price - exact).abs(), standardError: mc.standardError);
      }

      final ({double bias, double standardError}) coarse = runWith(2);
      final ({double bias, double standardError}) fine = runWith(200);

      // The coarse run is wrong by far more than its own error bar admits —
      // it is confidently off, which is exactly the trap.
      expect(coarse.bias, greaterThan(3 * coarse.standardError));
      // The fine run is not.
      expect(fine.bias, lessThan(3 * fine.standardError));
      expect(fine.bias, lessThan(coarse.bias));
    });

    test('an Asian option under Heston is cheaper than its European twin', () {
      const McSettings settings = McSettings(
        paths: 30000,
        steps: 120,
        seed: 65,
      );
      final double european = hestonMonteCarloPrice(
        OptionType.call,
        params: caseA,
        spot: 100,
        strike: 100,
        rate: 0.02,
        timeToExpiry: 1,
        settings: settings,
      ).price;
      final double asian = hestonMonteCarloPrice(
        OptionType.call,
        params: caseA,
        spot: 100,
        strike: 100,
        rate: 0.02,
        timeToExpiry: 1,
        payoff: HestonPayoff.asianArithmetic,
        settings: settings,
      ).price;

      expect(asian, lessThan(european));
      expect(asian, greaterThan(0));
    });

    test('the same seed gives the same price', () {
      const McSettings settings = McSettings(paths: 4000, steps: 40, seed: 66);
      double run() => hestonMonteCarloPrice(
        OptionType.call,
        params: caseA,
        spot: 100,
        strike: 100,
        rate: 0.02,
        timeToExpiry: 1,
        settings: settings,
      ).price;
      expect(run(), run());
    });
  });

  group('HestonParams', () {
    test('reports the Feller condition', () {
      // 2 * 1.5 * 0.04 = 0.12 > 0.09 = 0.3^2, so variance never reaches zero.
      expect(caseA.satisfiesFeller, isTrue);
      // Raising vol-of-vol past that point lets it touch zero.
      expect(caseA.copyWith(volOfVol: 0.6).satisfiesFeller, isFalse);
      // The equity-like default deliberately violates it, as real market
      // fits routinely do.
      expect(HestonParams.equityLike.satisfiesFeller, isFalse);
    });

    test('converts variance to the volatility people actually quote', () {
      expect(HestonParams.equityLike.initialVolatility, closeTo(0.25, 1e-12));
      expect(HestonParams.equityLike.longRunVolatility, closeTo(0.25, 1e-12));
    });

    test('still prices sanely when Feller is violated', () {
      // Variance visiting zero must not produce a NaN, an infinity or a
      // negative price — this is the parameter region real calibrations land
      // in, so it cannot be treated as an edge case.
      final HestonParams violating = caseA.copyWith(volOfVol: 1.2);
      expect(violating.satisfiesFeller, isFalse);

      final double price = hestonVanillaPrice(
        OptionType.call,
        params: violating,
        spot: 100,
        strike: 100,
        rate: 0.02,
        timeToExpiry: 2,
      );
      expect(price.isFinite, isTrue);
      expect(price, greaterThan(0));

      final McEstimate mc = hestonMonteCarloPrice(
        OptionType.call,
        params: violating,
        spot: 100,
        strike: 100,
        rate: 0.02,
        timeToExpiry: 2,
        settings: const McSettings(paths: 20000, steps: 200, seed: 67),
      );
      expect(mc.price.isFinite, isTrue);
      expect(mc.price, greaterThan(0));
    });
  });
}
