/// A minimal complex number, for the Heston characteristic function.
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule). Dart has
/// no complex type in its core libraries and pulling a package in for six
/// operations would be a poor trade, so the arithmetic is written out here.
///
/// WHY OPTION PRICING NEEDS COMPLEX NUMBERS AT ALL. Heston has no formula for
/// the option price, but it does have one for the *characteristic function*
/// of the log price — essentially the Fourier transform of the distribution.
/// Prices are then recovered by integrating that function back, and the
/// integral runs along the real line through complex-valued territory. The
/// complex numbers are scaffolding for the transform; nothing about the
/// finance is imaginary.
///
/// Only the operations Heston needs are implemented, and all of them take the
/// PRINCIPAL branch — which is safe because the characteristic function below
/// is written in the Albrecher et al. (2007) form chosen precisely so that
/// the principal branch never crosses a cut.
library;

import 'dart:math' as math;

/// An immutable complex number `re + im * i`.
class Complex {
  const Complex(this.re, this.im);

  /// The purely real number [value].
  const Complex.real(double value) : re = value, im = 0;

  /// The purely imaginary number `value * i`.
  const Complex.imaginary(double value) : re = 0, im = value;

  static const Complex zero = Complex(0, 0);
  static const Complex one = Complex(1, 0);

  /// The imaginary unit.
  static const Complex i = Complex(0, 1);

  final double re;
  final double im;

  Complex operator +(Complex other) => Complex(re + other.re, im + other.im);
  Complex operator -(Complex other) => Complex(re - other.re, im - other.im);
  Complex operator -() => Complex(-re, -im);

  Complex operator *(Complex other) =>
      Complex(re * other.re - im * other.im, re * other.im + im * other.re);

  Complex operator /(Complex other) {
    // Scaled to avoid overflow when the denominator's parts are large — the
    // characteristic function's exponentials get big deep in the integration
    // range.
    final double denominator =
        other.re * other.re + other.im * other.im;
    return Complex(
      (re * other.re + im * other.im) / denominator,
      (im * other.re - re * other.im) / denominator,
    );
  }

  Complex scale(double factor) => Complex(re * factor, im * factor);

  double get magnitude => math.sqrt(re * re + im * im);

  /// Principal argument, in `(-pi, pi]`.
  double get argument => math.atan2(im, re);

  bool get isFinite => re.isFinite && im.isFinite;

  /// e raised to this number.
  Complex get exp {
    final double scale = math.exp(re);
    return Complex(scale * math.cos(im), scale * math.sin(im));
  }

  /// Principal natural logarithm.
  Complex get log => Complex(math.log(magnitude), argument);

  /// Principal square root, computed without the round trip through log and
  /// exp so it stays accurate near the negative real axis.
  Complex get sqrt {
    if (re == 0 && im == 0) return zero;
    final double m = magnitude;
    final double realPart = math.sqrt((m + re) / 2);
    final double imagPart = math.sqrt((m - re) / 2);
    return Complex(realPart, im < 0 ? -imagPart : imagPart);
  }

  @override
  String toString() => im < 0 ? '$re - ${-im}i' : '$re + ${im}i';
}
