import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/barrier.dart';
import 'package:optionsschool/pricing/black_scholes.dart';

/// Reference values are computed independently of this package, in Python,
/// using `math.erf` rather than the Abramowitz & Stegun approximation the
/// Dart code uses — so a bug shared between the two implementations cannot
/// hide itself. The Python transcription of Reiner & Rubinstein (1991) was
/// separately checked to reproduce the plain Black-Scholes-Merton vanilla
/// when the barrier terms cancel.
///
/// Parameters throughout: S=100, r=8%, q=4%, sigma=30%, T=0.5 years — the
/// shape of the worked barrier examples in Haug, "The Complete Guide to
/// Option Pricing Formulas".
void main() {
  BsmInputs inputs(double strike) => BsmInputs(
    spot: 100,
    strike: strike,
    rate: 0.08,
    volatility: 0.30,
    timeToExpiry: 0.5,
    dividendYield: 0.04,
  );

  double price(
    OptionType type,
    BarrierDirection direction,
    BarrierStyle style,
    double barrier,
    double strike,
  ) => barrierPrice(
    BarrierSpec(
      type: type,
      direction: direction,
      style: style,
      barrier: barrier,
    ),
    inputs(strike),
  );

  group('closed form matches independent reference values', () {
    test('down barrier at 95', () {
      expect(
        price(OptionType.call, BarrierDirection.down, BarrierStyle.knockOut, 95, 90),
        closeTo(6.4163675922, 1e-4),
      );
      expect(
        price(OptionType.call, BarrierDirection.down, BarrierStyle.knockIn, 95, 90),
        closeTo(8.4652532128, 1e-4),
      );
      expect(
        price(OptionType.call, BarrierDirection.down, BarrierStyle.knockOut, 95, 100),
        closeTo(4.6115498852, 1e-4),
      );
      expect(
        price(OptionType.call, BarrierDirection.down, BarrierStyle.knockIn, 95, 100),
        closeTo(4.5929474150, 1e-4),
      );
      expect(
        price(OptionType.put, BarrierDirection.down, BarrierStyle.knockOut, 95, 110),
        closeTo(0.2076165035, 1e-4),
      );
      expect(
        price(OptionType.put, BarrierDirection.down, BarrierStyle.knockIn, 95, 110),
        closeTo(12.7636557328, 1e-4),
      );
    });

    test('up barrier at 105', () {
      expect(
        price(OptionType.call, BarrierDirection.up, BarrierStyle.knockOut, 105, 90),
        closeTo(0.2025092728, 1e-4),
      );
      expect(
        price(OptionType.call, BarrierDirection.up, BarrierStyle.knockIn, 105, 90),
        closeTo(14.6791115322, 1e-4),
      );
      expect(
        price(OptionType.put, BarrierDirection.up, BarrierStyle.knockOut, 105, 100),
        closeTo(3.3717193277, 1e-4),
      );
      expect(
        price(OptionType.put, BarrierDirection.up, BarrierStyle.knockIn, 105, 100),
        closeTo(3.8918545570, 1e-4),
      );
      expect(
        price(OptionType.put, BarrierDirection.up, BarrierStyle.knockIn, 105, 110),
        closeTo(7.8378475077, 1e-4),
      );
    });
  });

  /// IN-OUT PARITY: hold both the knock-in and the knock-out of the same
  /// contract and you hold the vanilla, because exactly one of the two is
  /// alive at expiry. This is the single most useful invariant a barrier
  /// pricer has — it must hold for every combination, not just the easy ones.
  group('in + out = vanilla', () {
    test('across every direction, type, strike and barrier', () {
      for (final OptionType type in OptionType.values) {
        for (final double strike in <double>[80, 90, 100, 110, 120]) {
          final double vanilla = bsmQuote(type, inputs(strike)).price;

          for (final (BarrierDirection direction, double barrier) in <
            (BarrierDirection, double)
          >[
            (BarrierDirection.down, 80),
            (BarrierDirection.down, 90),
            (BarrierDirection.down, 99),
            (BarrierDirection.up, 101),
            (BarrierDirection.up, 110),
            (BarrierDirection.up, 130),
          ]) {
            final double knockIn = price(
              type, direction, BarrierStyle.knockIn, barrier, strike,
            );
            final double knockOut = price(
              type, direction, BarrierStyle.knockOut, barrier, strike,
            );
            expect(
              knockIn + knockOut,
              closeTo(vanilla, 1e-8),
              reason:
                  '$type ${direction.name} barrier=$barrier strike=$strike',
            );
          }
        }
      }
    });
  });

  group('boundary behaviour', () {
    test('a barrier far out of reach leaves the vanilla intact', () {
      final double vanilla = bsmQuote(OptionType.call, inputs(100)).price;
      // A down barrier at 1 is essentially unreachable in six months at 30%
      // vol, so the knock-out is the vanilla and the knock-in is worthless.
      expect(
        price(OptionType.call, BarrierDirection.down, BarrierStyle.knockOut, 1, 100),
        closeTo(vanilla, 1e-6),
      );
      expect(
        price(OptionType.call, BarrierDirection.down, BarrierStyle.knockIn, 1, 100),
        closeTo(0, 1e-6),
      );
    });

    test('a barrier already breached settles immediately', () {
      // Spot 100 with a down barrier at 105 means the level is already
      // through. Nothing is left to simulate: the knock-out is dead and the
      // knock-in has already become an ordinary option.
      final double vanillaCall = bsmQuote(OptionType.call, inputs(100)).price;
      final double vanillaPut = bsmQuote(OptionType.put, inputs(100)).price;

      expect(
        price(OptionType.call, BarrierDirection.down, BarrierStyle.knockOut, 105, 100),
        0,
      );
      expect(
        price(OptionType.call, BarrierDirection.down, BarrierStyle.knockIn, 105, 100),
        closeTo(vanillaCall, 1e-12),
      );
      expect(
        price(OptionType.put, BarrierDirection.up, BarrierStyle.knockOut, 95, 100),
        0,
      );
      expect(
        price(OptionType.put, BarrierDirection.up, BarrierStyle.knockIn, 95, 100),
        closeTo(vanillaPut, 1e-12),
      );
    });

    /// A contract that can never pay. To finish below a strike of 90 the
    /// price must first pass down through a barrier at 95, which kills it —
    /// so a down-and-out put struck below its own barrier is worth exactly
    /// nothing. Worth a test because it is the clearest possible illustration
    /// that "cheaper" and "better value" are different things (CLAUDE.md
    /// rule 2).
    test('a down-and-out put struck below its barrier is worthless', () {
      expect(
        price(OptionType.put, BarrierDirection.down, BarrierStyle.knockOut, 95, 90),
        closeTo(0, 1e-9),
      );
      // ...and its knock-in twin is therefore the whole vanilla.
      expect(
        price(OptionType.put, BarrierDirection.down, BarrierStyle.knockIn, 95, 90),
        closeTo(bsmQuote(OptionType.put, inputs(90)).price, 1e-8),
      );
    });

    test('an up-and-out call struck above its barrier is worthless', () {
      expect(
        price(OptionType.call, BarrierDirection.up, BarrierStyle.knockOut, 105, 110),
        closeTo(0, 1e-9),
      );
    });

    test('no barrier option is ever worth more than its vanilla, or less than nothing', () {
      for (final OptionType type in OptionType.values) {
        for (final double strike in <double>[85, 100, 115]) {
          final double vanilla = bsmQuote(type, inputs(strike)).price;
          for (final BarrierStyle style in BarrierStyle.values) {
            for (final (BarrierDirection d, double h) in <(BarrierDirection, double)>[
              (BarrierDirection.down, 85),
              (BarrierDirection.down, 95),
              (BarrierDirection.up, 108),
              (BarrierDirection.up, 125),
            ]) {
              final double p = price(type, d, style, h, strike);
              expect(p, greaterThanOrEqualTo(0));
              expect(p, lessThanOrEqualTo(vanilla + 1e-9));
            }
          }
        }
      }
    });
  });

  group('continuity correction', () {
    test('pushes the barrier away from the spot', () {
      // A down barrier moves down and an up barrier moves up: in both cases
      // further away, because a discretely watched barrier is harder to hit.
      expect(
        discreteEquivalentBarrier(
          95,
          direction: BarrierDirection.down,
          volatility: 0.3,
          timeToExpiry: 0.5,
          monitoringDates: 126,
        ),
        lessThan(95),
      );
      expect(
        discreteEquivalentBarrier(
          105,
          direction: BarrierDirection.up,
          volatility: 0.3,
          timeToExpiry: 0.5,
          monitoringDates: 126,
        ),
        greaterThan(105),
      );
    });

    test('shrinks towards no correction as monitoring gets finer', () {
      double gap(int dates) =>
          (discreteEquivalentBarrier(
            95,
            direction: BarrierDirection.down,
            volatility: 0.3,
            timeToExpiry: 0.5,
            monitoringDates: dates,
          ) -
          95).abs();

      expect(gap(10000), lessThan(gap(100)));
      expect(gap(100), lessThan(gap(4)));
      expect(gap(1000000), lessThan(0.02));
    });
  });

  test('spec labels read as English', () {
    expect(
      const BarrierSpec(
        type: OptionType.call,
        direction: BarrierDirection.down,
        style: BarrierStyle.knockOut,
        barrier: 90,
      ).label,
      'Down-and-out call',
    );
    expect(
      const BarrierSpec(
        type: OptionType.put,
        direction: BarrierDirection.up,
        style: BarrierStyle.knockIn,
        barrier: 120,
      ).label,
      'Up-and-in put',
    );
  });
}
