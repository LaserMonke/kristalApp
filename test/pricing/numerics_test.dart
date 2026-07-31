import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/complex.dart';
import 'package:optionsschool/pricing/quadrature.dart';

/// The two numerical utilities Heston is built on. They are tested on their
/// own because a fault in either would surface as a wrong option price with
/// nothing to point at the cause — and both have exact, checkable answers of
/// their own, which the pricing code does not.
void main() {
  group('Complex arithmetic', () {
    const Complex a = Complex(3, 4);
    const Complex b = Complex(-1, 2);

    test('adds, subtracts and negates', () {
      expect((a + b).re, 2);
      expect((a + b).im, 6);
      expect((a - b).re, 4);
      expect((a - b).im, 2);
      expect((-a).re, -3);
      expect((-a).im, -4);
    });

    test('multiplies', () {
      // (3+4i)(-1+2i) = -3+6i-4i+8i^2 = -11+2i
      expect((a * b).re, closeTo(-11, 1e-12));
      expect((a * b).im, closeTo(2, 1e-12));
    });

    test('divides, and division undoes multiplication', () {
      final Complex quotient = (a * b) / b;
      expect(quotient.re, closeTo(a.re, 1e-12));
      expect(quotient.im, closeTo(a.im, 1e-12));
    });

    test('reports magnitude and argument', () {
      expect(a.magnitude, closeTo(5, 1e-12));
      expect(const Complex(0, 2).argument, closeTo(math.pi / 2, 1e-12));
      expect(const Complex(-1, 0).argument, closeTo(math.pi, 1e-12));
    });

    test('exp satisfies Eulers identity', () {
      // e^(i*pi) = -1, the single most quotable fact in mathematics and a
      // sharp test of both cos and sin being wired in the right places.
      final Complex result = Complex.imaginary(math.pi).exp;
      expect(result.re, closeTo(-1, 1e-12));
      expect(result.im, closeTo(0, 1e-12));
    });

    test('log inverts exp for imaginary parts inside (-pi, pi]', () {
      for (final Complex z in <Complex>[
        const Complex(0.5, 0.3),
        const Complex(-2, 1),
        const Complex(1, -3),
        const Complex(-0.25, 3.1),
      ]) {
        final Complex round = z.exp.log;
        expect(round.re, closeTo(z.re, 1e-10));
        expect(round.im, closeTo(z.im, 1e-10));
      }
    });

    /// Outside that strip the round trip WRAPS, and that is correct rather
    /// than broken: the complex logarithm is many-valued and this one returns
    /// the principal value. It is stated as a test because the wrapping is
    /// exactly what makes Heston's original 1993 formulation misprice long
    /// maturities — `heston.dart` uses the Albrecher form specifically to
    /// stay inside the strip, and this records what the alternative costs.
    test('log wraps the imaginary part into the principal strip', () {
      final Complex round = const Complex(1, -4).exp.log;
      expect(round.re, closeTo(1, 1e-10));
      expect(round.im, closeTo(-4 + 2 * math.pi, 1e-10));
      expect(round.im, inInclusiveRange(-math.pi, math.pi));
    });

    test('sqrt squares back to what it came from', () {
      for (final Complex z in <Complex>[
        const Complex(3, 4),
        const Complex(-5, 12),
        // The dangerous one: just below the negative real axis, where a
        // careless implementation flips to the wrong branch.
        const Complex(-1, -1e-12),
        const Complex(0.0001, 0),
      ]) {
        final Complex root = z.sqrt;
        final Complex squared = root * root;
        expect(squared.re, closeTo(z.re, 1e-9));
        expect(squared.im, closeTo(z.im, 1e-9));
      }
    });

    test('sqrt of -1 is i, not -i', () {
      final Complex root = const Complex(-1, 0).sqrt;
      expect(root.re, closeTo(0, 1e-12));
      expect(root.im, closeTo(1, 1e-12));
    });

    test('sqrt of zero is zero', () {
      expect(Complex.zero.sqrt.re, 0);
      expect(Complex.zero.sqrt.im, 0);
    });

    test('scale multiplies both parts', () {
      expect(a.scale(2).re, 6);
      expect(a.scale(2).im, 8);
    });
  });

  group('Gauss-Legendre quadrature', () {
    test('weights sum to the width of the interval', () {
      for (final int n in <int>[2, 8, 32, 128]) {
        final GaussLegendreRule rule = gaussLegendre(n);
        expect(
          rule.weights.reduce((double a, double b) => a + b),
          closeTo(2, 1e-12),
          reason: 'n=$n',
        );
      }
    });

    test('nodes are symmetric about zero and inside the interval', () {
      final GaussLegendreRule rule = gaussLegendre(16);
      for (int i = 0; i < 16; i++) {
        expect(rule.nodes[i], closeTo(-rule.nodes[15 - i], 1e-12));
        expect(rule.nodes[i].abs(), lessThan(1));
      }
    });

    /// The defining property: an n-point rule integrates ANY polynomial up to
    /// degree 2n-1 exactly, not approximately. This is what makes it worth
    /// deriving rather than reaching for something simpler.
    test('is exact for polynomials up to degree 2n-1', () {
      const int n = 6;
      for (int degree = 0; degree <= 2 * n - 1; degree++) {
        final double numerical = integrate(
          (double x) => math.pow(x, degree).toDouble(),
          lower: -1,
          upper: 1,
          points: n,
        );
        // Integral of x^k over [-1, 1] is 0 for odd k, 2/(k+1) for even.
        final double exact = degree.isOdd ? 0 : 2 / (degree + 1);
        expect(numerical, closeTo(exact, 1e-12), reason: 'degree=$degree');
      }
    });

    test('handles a shifted interval', () {
      // Integral of x^2 from 1 to 4 is (64 - 1)/3 = 21.
      expect(
        integrate((double x) => x * x, lower: 1, upper: 4, points: 8),
        closeTo(21, 1e-10),
      );
    });

    test('integrates smooth transcendental functions accurately', () {
      // Integral of sin from 0 to pi is 2.
      expect(
        integrate(math.sin, lower: 0, upper: math.pi, points: 32),
        closeTo(2, 1e-12),
      );
      // Integral of e^x from 0 to 1 is e - 1.
      expect(
        integrate(math.exp, lower: 0, upper: 1, points: 32),
        closeTo(math.e - 1, 1e-12),
      );
      // A decaying integrand of the kind Heston's inversion produces.
      expect(
        integrate(
          (double x) => math.exp(-x) * math.cos(x),
          lower: 0,
          upper: 40,
          points: 128,
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('caches rules rather than rederiving them', () {
      // The interactive pricer asks for the same rule on every frame, so
      // identity here is a performance contract, not a curiosity.
      expect(identical(gaussLegendre(64), gaussLegendre(64)), isTrue);
    });

    test('odd orders place a node exactly at the centre', () {
      final GaussLegendreRule rule = gaussLegendre(7);
      expect(rule.nodes[3], closeTo(0, 1e-14));
    });
  });
}
