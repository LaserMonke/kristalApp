/// Black-Scholes-Merton pricing and Greeks for European options.
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule), so it is
/// directly unit-testable and shared by the interactive pricer (Phase 4),
/// lesson diagrams and — later — the practice market.
///
/// ASSUMPTIONS (state these wherever this output is shown — CLAUDE.md rule
/// 5, "model limitations stated"):
/// - European exercise only; no early exercise.
/// - No arbitrage, and continuous, frictionless trading with no transaction
///   costs or bid/ask spread.
/// - A constant, known volatility and a constant, known risk-free rate over
///   the life of the option.
/// - The underlying follows geometric Brownian motion (its price is
///   log-normally distributed at any future date) and pays a constant
///   continuous dividend yield, [BsmInputs.dividendYield] — 0 by default,
///   meaning no dividends.
///
/// This is a MODEL, not a market. Real option prices differ because of
/// bid/ask spreads, discrete (not continuous) dividends, early exercise on
/// American-style contracts, price jumps, and volatility that is neither
/// constant nor known in advance (CLAUDE.md rule 4).
library;

import 'dart:math' as math;

/// The right conveyed by a European option.
enum OptionType {
  /// Right to buy the underlying at the strike.
  call,

  /// Right to sell the underlying at the strike.
  put,
}

/// The inputs Black-Scholes-Merton needs, plus the constant-dividend-yield
/// extension due to Merton (1973).
class BsmInputs {
  const BsmInputs({
    required this.spot,
    required this.strike,
    required this.rate,
    required this.volatility,
    required this.timeToExpiry,
    this.dividendYield = 0,
  }) : assert(spot > 0, 'spot must be positive'),
       assert(strike > 0, 'strike must be positive'),
       assert(volatility > 0, 'volatility must be positive'),
       assert(
         timeToExpiry > 0,
         'timeToExpiry must be positive — this model prices before expiry; '
         'use lib/pricing/payoff.dart for the value at expiry',
       );

  /// Current price of the underlying.
  final double spot;

  /// Exercise price.
  final double strike;

  /// Continuously-compounded, annualised risk-free rate (0.05 = 5%).
  final double rate;

  /// Annualised volatility of the underlying's returns (0.20 = 20%).
  final double volatility;

  /// Time to expiry in years (0.5 = six months).
  final double timeToExpiry;

  /// Continuous dividend yield (0.02 = 2%). 0 (the default) means the
  /// underlying pays no dividends.
  final double dividendYield;

  double get _sqrtT => math.sqrt(timeToExpiry);

  /// d1 term of the Black-Scholes-Merton formula.
  double get d1 =>
      (math.log(spot / strike) +
          (rate - dividendYield + 0.5 * volatility * volatility) *
              timeToExpiry) /
      (volatility * _sqrtT);

  /// d2 = d1 - sigma * sqrt(T).
  double get d2 => d1 - volatility * _sqrtT;
}

/// Price and Greeks for one option, computed together so the shared d1, d2,
/// N(.) and phi(.) terms are worked out once rather than per Greek — the
/// interactive pricer (Phase 4) recomputes this on every slider tick.
class BsmQuote {
  const BsmQuote({
    required this.price,
    required this.delta,
    required this.gamma,
    required this.vega,
    required this.theta,
    required this.rho,
  });

  /// Theoretical option price under the model.
  final double price;

  /// Change in price per 1.00 change in the underlying.
  final double delta;

  /// Change in delta per 1.00 change in the underlying.
  final double gamma;

  /// Change in price per 1.00 (100 percentage points) change in volatility.
  /// Divide by 100 for the "per 1 vol point" figure traders usually quote.
  final double vega;

  /// Change in price per year of time passing. A "per calendar day" figure
  /// is theta / 365. Negative for most long option positions — the
  /// well-known effect of time decay.
  final double theta;

  /// Change in price per 1.00 (100 percentage points) change in the
  /// risk-free rate. Divide by 100 for the "per 1% rate move" figure.
  final double rho;
}

/// Prices a European [type] option under [inputs] and its Greeks.
BsmQuote bsmQuote(OptionType type, BsmInputs inputs) {
  final double s = inputs.spot;
  final double k = inputs.strike;
  final double r = inputs.rate;
  final double q = inputs.dividendYield;
  final double sigma = inputs.volatility;
  final double t = inputs.timeToExpiry;
  final double sqrtT = math.sqrt(t);

  final double d1 = inputs.d1;
  final double d2 = inputs.d2;
  final double discountR = math.exp(-r * t);
  final double discountQ = math.exp(-q * t);
  final double pdfD1 = normalPdf(d1);

  final double nD1 = normalCdf(d1);
  final double nD2 = normalCdf(d2);
  final double nNegD1 = normalCdf(-d1);
  final double nNegD2 = normalCdf(-d2);

  // Everything that differs between a call and a put — price, delta, theta
  // and rho — falls out of put-call symmetry; gamma and vega are identical
  // for both, so they are computed once below.
  final (double price, double delta, double theta, double rho) = switch (type) {
    OptionType.call => (
      s * discountQ * nD1 - k * discountR * nD2,
      discountQ * nD1,
      -s * discountQ * pdfD1 * sigma / (2 * sqrtT) -
          r * k * discountR * nD2 +
          q * s * discountQ * nD1,
      k * t * discountR * nD2,
    ),
    OptionType.put => (
      k * discountR * nNegD2 - s * discountQ * nNegD1,
      discountQ * (nD1 - 1),
      -s * discountQ * pdfD1 * sigma / (2 * sqrtT) +
          r * k * discountR * nNegD2 -
          q * s * discountQ * nNegD1,
      -k * t * discountR * nNegD2,
    ),
  };

  final double gamma = discountQ * pdfD1 / (s * sigma * sqrtT);
  final double vega = s * discountQ * pdfD1 * sqrtT;

  return BsmQuote(
    price: price,
    delta: delta,
    gamma: gamma,
    vega: vega,
    theta: theta,
    rho: rho,
  );
}

/// Standard normal probability density function, phi(x).
double normalPdf(double x) => math.exp(-x * x / 2) / math.sqrt(2 * math.pi);

/// Standard normal cumulative distribution function, Phi(x).
///
/// Abramowitz & Stegun formula 26.2.17 (Handbook of Mathematical Functions,
/// 1964) — a rational polynomial approximation with maximum absolute error
/// 7.5e-8, ample precision for pricing. dart:math has no built-in erf, so
/// this is worked out directly rather than pulled in from a package.
double normalCdf(double x) {
  final bool negative = x < 0;
  final double z = negative ? -x : x;

  const double b1 = 0.319381530;
  const double b2 = -0.356563782;
  const double b3 = 1.781477937;
  const double b4 = -1.821255978;
  const double b5 = 1.330274429;
  const double p = 0.2316419;

  final double tt = 1 / (1 + p * z);
  final double poly = tt * (b1 + tt * (b2 + tt * (b3 + tt * (b4 + tt * b5))));
  final double cdf = 1 - normalPdf(z) * poly;

  return negative ? 1 - cdf : cdf;
}
