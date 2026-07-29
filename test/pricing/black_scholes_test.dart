import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/black_scholes.dart';

/// Reference values are computed independently of this package, in Python,
/// using `math.erf` (not the Abramowitz & Stegun approximation under test
/// here) so a bug shared between the two implementations can't hide itself:
///
/// ```python
/// import math
/// def bsm(S, K, r, sigma, T, q=0.0):
///     d1 = (math.log(S/K) + (r - q + 0.5*sigma*sigma)*T) / (sigma*math.sqrt(T))
///     d2 = d1 - sigma*math.sqrt(T)
///     N = lambda x: 0.5*(1+math.erf(x/math.sqrt(2)))
///     ...
/// ```
///
/// The "Hull classic" case is the worked Black-Scholes-Merton example from
/// Hull, "Options, Futures, and Other Derivatives" (S=42, K=40, r=10%,
/// sigma=20%, T=6 months): the textbook quotes call = 4.76, put = 0.81,
/// matching the higher-precision values below.
void main() {
  group('Hull classic — S=42, K=40, r=10%, sigma=20%, T=0.5y, no dividend', () {
    const BsmInputs inputs = BsmInputs(
      spot: 42,
      strike: 40,
      rate: 0.10,
      volatility: 0.20,
      timeToExpiry: 0.5,
    );

    test('call price matches the textbook value (4.76)', () {
      final BsmQuote q = bsmQuote(OptionType.call, inputs);
      expect(q.price, closeTo(4.7594223929, 1e-3));
    });

    test('put price matches the textbook value (0.81)', () {
      final BsmQuote q = bsmQuote(OptionType.put, inputs);
      expect(q.price, closeTo(0.8085993729, 1e-3));
    });

    test('call Greeks', () {
      final BsmQuote q = bsmQuote(OptionType.call, inputs);
      expect(q.delta, closeTo(0.7791312909, 1e-3));
      expect(q.gamma, closeTo(0.0499626704, 1e-3));
      expect(q.vega, closeTo(8.8134150596, 1e-2));
      expect(q.theta, closeTo(-4.5590921946, 1e-2));
      expect(q.rho, closeTo(13.9820459134, 1e-2));
    });

    test('put Greeks', () {
      final BsmQuote q = bsmQuote(OptionType.put, inputs);
      expect(q.delta, closeTo(-0.2208687091, 1e-3));
      expect(q.gamma, closeTo(0.0499626704, 1e-3));
      expect(q.vega, closeTo(8.8134150596, 1e-2));
      expect(q.theta, closeTo(-0.7541744966, 1e-2));
      expect(q.rho, closeTo(-5.0425425767, 1e-2));
    });
  });

  group('at-the-money — S=K=100, r=5%, sigma=25%, T=1y, no dividend', () {
    const BsmInputs inputs = BsmInputs(
      spot: 100,
      strike: 100,
      rate: 0.05,
      volatility: 0.25,
      timeToExpiry: 1.0,
    );

    test('call price', () {
      expect(
        bsmQuote(OptionType.call, inputs).price,
        closeTo(12.3359989304, 1e-3),
      );
    });

    test('put price', () {
      expect(
        bsmQuote(OptionType.put, inputs).price,
        closeTo(7.4589413804, 1e-3),
      );
    });

    test('gamma and vega are identical for the call and the put', () {
      final BsmQuote c = bsmQuote(OptionType.call, inputs);
      final BsmQuote p = bsmQuote(OptionType.put, inputs);
      expect(c.gamma, closeTo(p.gamma, 1e-9));
      expect(c.vega, closeTo(p.vega, 1e-9));
      expect(c.gamma, closeTo(0.0151367933, 1e-3));
      expect(c.vega, closeTo(37.8419831934, 1e-2));
    });
  });

  group('with a continuous dividend yield — S=K=50, r=3%, sigma=30%, T=1y, q=2%', () {
    const BsmInputs inputs = BsmInputs(
      spot: 50,
      strike: 50,
      rate: 0.03,
      volatility: 0.30,
      timeToExpiry: 1.0,
      dividendYield: 0.02,
    );

    test('call price', () {
      expect(
        bsmQuote(OptionType.call, inputs).price,
        closeTo(6.0616796796, 1e-3),
      );
    });

    test('put price', () {
      expect(
        bsmQuote(OptionType.put, inputs).price,
        closeTo(5.5740226916, 1e-3),
      );
    });

    test('call delta', () {
      expect(
        bsmQuote(OptionType.call, inputs).delta,
        closeTo(0.5613909106, 1e-3),
      );
    });
  });

  group('short-dated, out-of-the-money — S=100, K=90, r=2%, sigma=35%, T=0.1y', () {
    const BsmInputs inputs = BsmInputs(
      spot: 100,
      strike: 90,
      rate: 0.02,
      volatility: 0.35,
      timeToExpiry: 0.1,
    );

    test('call price', () {
      expect(
        bsmQuote(OptionType.call, inputs).price,
        closeTo(11.1039298901, 1e-3),
      );
    });

    test('put price', () {
      expect(
        bsmQuote(OptionType.put, inputs).price,
        closeTo(0.9241097701, 1e-3),
      );
    });
  });

  group('put-call parity: C - P = S*exp(-qT) - K*exp(-rT)', () {
    // This must hold for ANY valid inputs — it follows from a static
    // replication argument, not from the Black-Scholes model itself — so
    // it is a strong check that the call and put formulas are consistent
    // with each other, independent of the textbook reference values.
    for (final BsmInputs inputs in <BsmInputs>[
      const BsmInputs(spot: 42, strike: 40, rate: 0.10, volatility: 0.20, timeToExpiry: 0.5),
      const BsmInputs(spot: 100, strike: 100, rate: 0.05, volatility: 0.25, timeToExpiry: 1.0),
      const BsmInputs(spot: 50, strike: 50, rate: 0.03, volatility: 0.30, timeToExpiry: 1.0, dividendYield: 0.02),
      const BsmInputs(spot: 100, strike: 90, rate: 0.02, volatility: 0.35, timeToExpiry: 0.1),
      const BsmInputs(spot: 25, strike: 60, rate: 0.01, volatility: 0.6, timeToExpiry: 2.0),
    ]) {
      test('holds for spot=${inputs.spot}, strike=${inputs.strike}', () {
        final double call = bsmQuote(OptionType.call, inputs).price;
        final double put = bsmQuote(OptionType.put, inputs).price;
        final double forward =
            inputs.spot * math.exp(-inputs.dividendYield * inputs.timeToExpiry) -
            inputs.strike * math.exp(-inputs.rate * inputs.timeToExpiry);
        expect(call - put, closeTo(forward, 1e-6));
      });
    }
  });

  group('sanity bounds', () {
    test('deep in-the-money call delta approaches 1', () {
      const BsmInputs inputs = BsmInputs(
        spot: 500,
        strike: 100,
        rate: 0.03,
        volatility: 0.2,
        timeToExpiry: 0.5,
      );
      expect(bsmQuote(OptionType.call, inputs).delta, closeTo(1, 1e-6));
    });

    test('deep out-of-the-money call delta approaches 0', () {
      const BsmInputs inputs = BsmInputs(
        spot: 20,
        strike: 100,
        rate: 0.03,
        volatility: 0.2,
        timeToExpiry: 0.5,
      );
      expect(bsmQuote(OptionType.call, inputs).delta, closeTo(0, 1e-6));
    });

    test('gamma and vega are never negative', () {
      const BsmInputs inputs = BsmInputs(
        spot: 80,
        strike: 120,
        rate: 0.04,
        volatility: 0.45,
        timeToExpiry: 0.75,
      );
      final BsmQuote c = bsmQuote(OptionType.call, inputs);
      expect(c.gamma, greaterThanOrEqualTo(0));
      expect(c.vega, greaterThanOrEqualTo(0));
    });

    test('put delta is always call delta minus exp(-qT)', () {
      const BsmInputs inputs = BsmInputs(
        spot: 65,
        strike: 70,
        rate: 0.02,
        volatility: 0.3,
        timeToExpiry: 0.4,
        dividendYield: 0.01,
      );
      final BsmQuote c = bsmQuote(OptionType.call, inputs);
      final BsmQuote p = bsmQuote(OptionType.put, inputs);
      final double discountQ = math.exp(-inputs.dividendYield * inputs.timeToExpiry);
      expect(p.delta, closeTo(c.delta - discountQ, 1e-9));
    });
  });

  group('normalCdf / normalPdf', () {
    test('Phi(0) is exactly one half', () {
      expect(normalCdf(0), closeTo(0.5, 1e-9));
    });

    test('Phi is antisymmetric about 0.5', () {
      for (final double x in <double>[0.3, 1.1, 2.5, -0.7]) {
        expect(normalCdf(-x), closeTo(1 - normalCdf(x), 1e-9));
      }
    });

    test('matches known standard-normal table values', () {
      expect(normalCdf(1.0), closeTo(0.8413447461, 1e-6));
      expect(normalCdf(1.96), closeTo(0.9750021049, 1e-6));
      expect(normalCdf(-1.96), closeTo(0.0249978951, 1e-6));
    });

    test('pdf is symmetric and peaks at 0', () {
      expect(normalPdf(0), closeTo(0.3989422804, 1e-9));
      expect(normalPdf(1.5), closeTo(normalPdf(-1.5), 1e-12));
    });
  });
}
