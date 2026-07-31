import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/basket.dart';
import 'package:optionsschool/pricing/black_scholes.dart';
import 'package:optionsschool/pricing/monte_carlo.dart';

/// A basket pricer has no textbook number to check against for the payoff
/// people actually trade (the arithmetic basket has no closed form — that is
/// why it is simulated). So it is pinned down three other ways:
///
///   1. Against the ONE case that does have an exact formula, the geometric
///      basket, whose reference values are computed independently in Python
///      with `math.erf`.
///   2. Against Black-Scholes-Merton in the degenerate cases where a basket
///      collapses to a single asset — one member, or perfectly correlated
///      identical members.
///   3. Against economic inequalities that must hold whatever the numbers:
///      diversification lowers the price, a basket option is never dearer
///      than the options on its parts, arithmetic never below geometric.
void main() {
  List<BasketAsset> threeAssets() => const <BasketAsset>[
    BasketAsset(spot: 100, volatility: 0.20, weight: 0.5),
    BasketAsset(spot: 95, volatility: 0.30, weight: 0.3, dividendYield: 0.02),
    BasketAsset(spot: 110, volatility: 0.25, weight: 0.2, dividendYield: 0.01),
  ];

  BasketSpec threeAssetSpec({
    OptionType type = OptionType.call,
    double rho = 0.35,
    BasketAverage average = BasketAverage.geometric,
  }) => BasketSpec(
    assets: threeAssets(),
    correlation: uniformCorrelation(3, rho),
    strike: 100,
    type: type,
    rate: 0.04,
    timeToExpiry: 0.75,
    average: average,
  );

  group('geometric basket closed form vs independent reference values', () {
    test('call and put, three assets, correlation 0.35', () {
      expect(
        geometricBasketPrice(threeAssetSpec()),
        closeTo(7.1083295121, 1e-4),
      );
      expect(
        geometricBasketPrice(threeAssetSpec(type: OptionType.put)),
        closeTo(5.3513634220, 1e-4),
      );
    });

    test('effective volatility matches the quadratic form', () {
      expect(
        threeAssetSpec().effectiveVolatility,
        closeTo(0.1831665908, 1e-9),
      );
    });
  });

  group('collapses to Black-Scholes when it should', () {
    test('a one-asset basket is just a vanilla option', () {
      const BsmInputs single = BsmInputs(
        spot: 100,
        strike: 105,
        rate: 0.05,
        volatility: 0.25,
        timeToExpiry: 1,
      );
      final BasketSpec spec = BasketSpec(
        assets: const <BasketAsset>[
          BasketAsset(spot: 100, volatility: 0.25, weight: 1),
        ],
        correlation: uniformCorrelation(1, 0),
        strike: 105,
        type: OptionType.call,
        rate: 0.05,
        timeToExpiry: 1,
      );

      // With one member the arithmetic and geometric blends are the same
      // thing, so the closed form must reproduce Black-Scholes exactly.
      expect(
        geometricBasketPrice(spec),
        closeTo(bsmQuote(OptionType.call, single).price, 1e-9),
      );

      final McEstimate mc = basketMonteCarloPrice(
        spec,
        settings: const McSettings(paths: 100000, steps: 1, seed: 51),
      );
      expect(
        (mc.price - bsmQuote(OptionType.call, single).price).abs(),
        lessThan(3 * mc.standardError),
      );
    });

    test('perfectly correlated identical assets behave as one asset', () {
      // Correlation 1 means the members never diversify anything: the basket
      // moves exactly as one member does, so its option must cost the same.
      const BsmInputs single = BsmInputs(
        spot: 100,
        strike: 100,
        rate: 0.05,
        volatility: 0.25,
        timeToExpiry: 1,
      );
      final BasketSpec spec = BasketSpec(
        assets: const <BasketAsset>[
          BasketAsset(spot: 100, volatility: 0.25, weight: 1),
          BasketAsset(spot: 100, volatility: 0.25, weight: 1),
          BasketAsset(spot: 100, volatility: 0.25, weight: 1),
        ],
        correlation: uniformCorrelation(3, 1),
        strike: 100,
        type: OptionType.call,
        rate: 0.05,
        timeToExpiry: 1,
        average: BasketAverage.arithmetic,
      );

      expect(spec.effectiveVolatility, closeTo(0.25, 1e-9));

      final McEstimate mc = basketMonteCarloPrice(
        spec,
        settings: const McSettings(paths: 100000, steps: 1, seed: 52),
      );
      expect(
        (mc.price - bsmQuote(OptionType.call, single).price).abs(),
        lessThan(3 * mc.standardError),
      );
    });
  });

  group('simulation agrees with the closed form where both apply', () {
    test('geometric basket, three correlated assets', () {
      final BasketSpec spec = threeAssetSpec();
      final double exact = geometricBasketPrice(spec);
      final McEstimate mc = basketMonteCarloPrice(
        spec,
        settings: const McSettings(paths: 200000, steps: 1, seed: 53),
      );

      expect((mc.price - exact).abs(), lessThan(3 * mc.standardError));
    });

    test('and for the put as well', () {
      final BasketSpec spec = threeAssetSpec(type: OptionType.put);
      final double exact = geometricBasketPrice(spec);
      final McEstimate mc = basketMonteCarloPrice(
        spec,
        settings: const McSettings(paths: 200000, steps: 1, seed: 54),
      );

      expect((mc.price - exact).abs(), lessThan(3 * mc.standardError));
    });

    test('at zero correlation too, where diversification is strongest', () {
      final BasketSpec spec = threeAssetSpec(rho: 0);
      final double exact = geometricBasketPrice(spec);
      final McEstimate mc = basketMonteCarloPrice(
        spec,
        settings: const McSettings(paths: 200000, steps: 1, seed: 55),
      );

      expect((mc.price - exact).abs(), lessThan(3 * mc.standardError));
    });
  });

  group('the economics hold', () {
    /// The headline lesson of a basket option: assets that move together
    /// make the blend volatile and the option dear; assets that move
    /// independently steady the blend and make it cheap. Correlation is the
    /// price.
    test('lower correlation means a cheaper option', () {
      double priceAt(double rho) => geometricBasketPrice(
        threeAssetSpec(rho: rho),
      );

      final List<double> prices = <double>[
        for (final double rho in <double>[0.0, 0.25, 0.5, 0.75, 1.0])
          priceAt(rho),
      ];
      for (int i = 1; i < prices.length; i++) {
        expect(prices[i], greaterThan(prices[i - 1]));
      }
    });

    test('effective volatility sits below the weighted average unless rho is 1', () {
      final BasketSpec spec = threeAssetSpec(rho: 0.35);
      final List<double> w = spec.normalisedWeights;
      double weightedVol = 0;
      for (int i = 0; i < spec.size; i++) {
        weightedVol += w[i] * spec.assets[i].volatility;
      }

      expect(spec.effectiveVolatility, lessThan(weightedVol));
      // ...and reaches it exactly when nothing diversifies.
      expect(
        threeAssetSpec(rho: 1).effectiveVolatility,
        closeTo(weightedVol, 1e-9),
      );
    });

    test('a basket option costs no more than the options on its parts', () {
      // Buying one option on the blend can never beat buying the weighted
      // basket of individual options, because the individual options let you
      // keep each winner while walking away from each loser. The gap is what
      // you give up for the lower premium.
      final BasketSpec spec = threeAssetSpec(
        average: BasketAverage.arithmetic,
      );
      final List<double> w = spec.normalisedWeights;

      double sumOfParts = 0;
      for (int i = 0; i < spec.size; i++) {
        final BasketAsset a = spec.assets[i];
        sumOfParts +=
            w[i] *
            bsmQuote(
              OptionType.call,
              BsmInputs(
                spot: a.spot,
                // Each part is struck at its own share of the basket strike,
                // so the two positions are directly comparable.
                strike: spec.strike,
                rate: spec.rate,
                volatility: a.volatility,
                timeToExpiry: spec.timeToExpiry,
                dividendYield: a.dividendYield,
              ),
            ).price;
      }

      final McEstimate basket = basketMonteCarloPrice(
        spec,
        settings: const McSettings(paths: 100000, steps: 1, seed: 56),
      );
      expect(basket.price, lessThan(sumOfParts));
    });

    test('the arithmetic basket is never worth less than the geometric one', () {
      // AM-GM holds path by path, so with a shared seed it holds for the
      // prices too — and it is what makes the geometric price a usable fast
      // lower bound for the arithmetic one.
      const McSettings settings = McSettings(paths: 60000, steps: 1, seed: 57);
      final double arithmetic = basketMonteCarloPrice(
        threeAssetSpec(average: BasketAverage.arithmetic),
        settings: settings,
      ).price;
      final double geometric = basketMonteCarloPrice(
        threeAssetSpec(),
        settings: settings,
      ).price;

      expect(arithmetic, greaterThan(geometric));
      expect(
        geometric,
        closeTo(geometricBasketPrice(threeAssetSpec()), 0.05),
      );
    });
  });

  group('Cholesky decomposition', () {
    test('reconstructs the matrix it came from', () {
      final List<List<double>> matrix = uniformCorrelation(4, 0.4);
      final List<List<double>> l = choleskyDecompose(matrix);

      for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
          double sum = 0;
          for (int k = 0; k < 4; k++) {
            sum += l[i][k] * l[j][k];
          }
          expect(sum, closeTo(matrix[i][j], 1e-12));
        }
      }
    });

    test('is lower triangular', () {
      final List<List<double>> l = choleskyDecompose(uniformCorrelation(3, 0.2));
      expect(l[0][1], 0);
      expect(l[0][2], 0);
      expect(l[1][2], 0);
    });

    test('handles the perfectly correlated case without blowing up', () {
      final List<List<double>> l = choleskyDecompose(uniformCorrelation(3, 1));
      expect(l[0][0], closeTo(1, 1e-12));
      // Rows 2 and 3 are copies of row 1 — the assets are redundant, not
      // contradictory, so this is a valid decomposition rather than an error.
      expect(l[1][1], closeTo(0, 1e-9));
      expect(l[2][2], closeTo(0, 1e-9));
    });

    /// Correlations are not free parameters: "A and B move together, B and C
    /// move together, A and C move oppositely" describes a world that cannot
    /// exist. A pricer that returned a number for it would be inventing one.
    test('refuses a correlation matrix that describes an impossible world', () {
      expect(
        () => choleskyDecompose(<List<double>>[
          <double>[1.0, 0.9, -0.9],
          <double>[0.9, 1.0, 0.9],
          <double>[-0.9, 0.9, 1.0],
        ]),
        throwsArgumentError,
      );
    });

    test('rejects a shared correlation below the -1/(n-1) floor', () {
      // Three assets cannot all be strongly negatively correlated with each
      // other: when A falls with B and B falls with C, A and C must move
      // together. The floor for n assets sharing one rho is -1/(n-1).
      expect(
        () => choleskyDecompose(uniformCorrelation(3, -0.9)),
        throwsArgumentError,
      );
      // Just inside the floor (-0.5 for three assets) is legitimate.
      expect(
        () => choleskyDecompose(uniformCorrelation(3, -0.45)),
        returnsNormally,
      );
    });
  });

  group('BasketSpec bookkeeping', () {
    test('normalises weights however they are entered', () {
      final BasketSpec spec = BasketSpec(
        assets: const <BasketAsset>[
          BasketAsset(spot: 100, volatility: 0.2, weight: 50),
          BasketAsset(spot: 100, volatility: 0.2, weight: 30),
          BasketAsset(spot: 100, volatility: 0.2, weight: 20),
        ],
        correlation: uniformCorrelation(3, 0.3),
        strike: 100,
        type: OptionType.call,
        rate: 0.04,
        timeToExpiry: 1,
      );

      expect(spec.normalisedWeights, <double>[0.5, 0.3, 0.2]);
      expect(
        spec.normalisedWeights.reduce((double a, double b) => a + b),
        closeTo(1, 1e-12),
      );
    });

    test('reports the blended level today', () {
      final BasketSpec spec = threeAssetSpec(
        average: BasketAverage.arithmetic,
      );
      // 0.5*100 + 0.3*95 + 0.2*110 = 100.5
      expect(spec.spotLevel, closeTo(100.5, 1e-12));

      // The geometric blend of the same members sits just below it, as the
      // AM-GM inequality requires.
      expect(threeAssetSpec().spotLevel, lessThan(100.5));
      expect(
        threeAssetSpec().spotLevel,
        closeTo(math.exp(0.5 * math.log(100) + 0.3 * math.log(95) + 0.2 * math.log(110)), 1e-12),
      );
    });
  });
}
