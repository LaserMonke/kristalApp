/// Gauss-Legendre quadrature: numerical integration for the Heston pricer.
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule).
///
/// WHY THIS AND NOT SOMETHING SIMPLER. Heston's price is an integral with no
/// closed form, and the interactive pricer re-evaluates it on every slider
/// tick — so it has to be both accurate and cheap. Gauss-Legendre with n
/// points is exact for any polynomial up to degree 2n-1, which for a smooth,
/// decaying integrand like Heston's buys accuracy that a trapezoid or Simpson
/// rule would need thousands of points to match.
///
/// The nodes and weights are DERIVED rather than pasted from a table: a
/// hand-copied table of 128 numbers is a place for a typo to sit undetected,
/// where a derivation can be tested against exact integrals it must reproduce.
library;

import 'dart:math' as math;

/// The evaluation points and weights of an n-point Gauss-Legendre rule on
/// `[-1, 1]`.
class GaussLegendreRule {
  const GaussLegendreRule(this.nodes, this.weights);

  final List<double> nodes;
  final List<double> weights;

  int get points => nodes.length;
}

/// Rules are expensive to derive and always the same, so each order is built
/// once and reused for the life of the process. The interactive pricer calls
/// this on every frame.
final Map<int, GaussLegendreRule> _cache = <int, GaussLegendreRule>{};

/// The n-point Gauss-Legendre rule on `[-1, 1]`.
///
/// The nodes are the roots of the n-th Legendre polynomial, found by Newton's
/// method from the Chebyshev-like starting guess `cos(pi (i - 1/4)/(n + 1/2))`,
/// which is close enough that a handful of iterations converge to machine
/// precision. The weights come from the derivative at each root.
GaussLegendreRule gaussLegendre(int n) {
  assert(n >= 2, 'need at least two points');
  final GaussLegendreRule? cached = _cache[n];
  if (cached != null) return cached;

  final List<double> nodes = List<double>.filled(n, 0);
  final List<double> weights = List<double>.filled(n, 0);

  // Roots are symmetric about zero, so only half of them need finding.
  final int half = (n + 1) ~/ 2;
  for (int i = 0; i < half; i++) {
    double x = math.cos(math.pi * (i + 0.75) / (n + 0.5));
    double derivative = 0;

    for (int iteration = 0; iteration < 100; iteration++) {
      // Legendre polynomials by their three-term recurrence:
      //   (k+1) P_{k+1} = (2k+1) x P_k - k P_{k-1}
      double p0 = 1;
      double p1 = 0;
      for (int k = 0; k < n; k++) {
        final double p2 = p1;
        p1 = p0;
        p0 = ((2 * k + 1) * x * p1 - k * p2) / (k + 1);
      }
      // P_n'(x), from the standard identity.
      derivative = n * (x * p0 - p1) / (x * x - 1);

      final double step = p0 / derivative;
      x -= step;
      if (step.abs() < 1e-15) break;
    }

    nodes[i] = -x;
    nodes[n - 1 - i] = x;
    final double weight = 2 / ((1 - x * x) * derivative * derivative);
    weights[i] = weight;
    weights[n - 1 - i] = weight;
  }

  final GaussLegendreRule rule = GaussLegendreRule(nodes, weights);
  _cache[n] = rule;
  return rule;
}

/// Integrates [f] over `[lower, upper]` with an n-point Gauss-Legendre rule.
double integrate(
  double Function(double x) f, {
  required double lower,
  required double upper,
  int points = 128,
}) {
  final GaussLegendreRule rule = gaussLegendre(points);
  // Map the rule's [-1, 1] nodes onto the requested interval.
  final double halfWidth = 0.5 * (upper - lower);
  final double centre = 0.5 * (upper + lower);

  double total = 0;
  for (int i = 0; i < rule.points; i++) {
    total += rule.weights[i] * f(centre + halfWidth * rule.nodes[i]);
  }
  return total * halfWidth;
}
