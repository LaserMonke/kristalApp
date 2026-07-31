import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/pricing/barrier.dart';
import 'package:optionsschool/pricing/black_scholes.dart';
import 'package:optionsschool/pricing/structured.dart';

/// Structured products are compositions, so the tests are mostly about the
/// composition being faithful: does the sum of the parts equal the whole,
/// does the payoff diagram agree with the components it was derived from, and
/// do the degenerate cases collapse to the plain instrument they should.
///
/// The final group tests the HONESTY claims, because on this instrument those
/// are the substance rather than a disclaimer bolted on afterwards
/// (CLAUDE.md rules 2 and 3).
void main() {
  const ProductMarket market = ProductMarket(
    spot: 100,
    volatility: 0.22,
    rate: 0.03,
    dividendYield: 0.02,
  );

  group('CapitalProtectedNote', () {
    test('with no participation it is just a zero-coupon bond', () {
      // Participation cannot be zero (a note with no upside is not a note),
      // so this checks the limit: as participation shrinks, the value falls
      // to the discounted protected amount and no further.
      const CapitalProtectedNote tiny = CapitalProtectedNote(
        participation: 1e-9,
        maturityYears: 5,
      );
      final StructuredValuation v = tiny.value(market);

      expect(v.fairValue, closeTo(100 * math.exp(-0.03 * 5), 1e-4));
    });

    test('the parts add up to the whole', () {
      const CapitalProtectedNote note = CapitalProtectedNote();
      final StructuredValuation v = note.value(market);

      double sum = 0;
      for (final ProductComponent c in v.components) {
        sum += c.value;
      }
      expect(v.fairValue, closeTo(sum, 1e-12));
      expect(v.components.length, 2);
    });

    test('a cap adds a SOLD component and lowers the value', () {
      const CapitalProtectedNote uncapped = CapitalProtectedNote();
      const CapitalProtectedNote capped = CapitalProtectedNote(capLevel: 130);

      final StructuredValuation capValuation = capped.value(market);
      expect(capValuation.components.length, 3);
      expect(capValuation.components.last.isSold, isTrue);
      expect(
        capValuation.fairValue,
        lessThan(uncapped.value(market).fairValue),
      );
    });

    /// The economics that killed these products when rates fell: the bond has
    /// to grow to the full notional by maturity, and at a low rate it costs
    /// almost the whole notional to buy, leaving nothing for options.
    test('a lower interest rate leaves less to spend on upside', () {
      const CapitalProtectedNote note = CapitalProtectedNote();

      double optionBudget(double rate) {
        final StructuredValuation v = note.value(
          market.copyWith(rate: rate),
        );
        return v.notional - v.components.first.value;
      }

      expect(optionBudget(0.001), lessThan(optionBudget(0.05)));
    });

    test('redemption never falls below the protected amount', () {
      const CapitalProtectedNote note = CapitalProtectedNote(
        protectionLevel: 1,
        participation: 0.7,
      );
      for (final double finish in <double>[1, 40, 80, 100, 150, 300]) {
        expect(
          note.redemptionAtExpiry(finish, initialSpot: 100),
          greaterThanOrEqualTo(100 - 1e-9),
          reason: 'finished at $finish',
        );
      }
    });

    test('redemption passes on exactly the participation share of a rise', () {
      const CapitalProtectedNote note = CapitalProtectedNote(
        participation: 0.7,
      );
      // A 20% rise, with 70% participation, pays 14% on top of the notional.
      expect(
        note.redemptionAtExpiry(120, initialSpot: 100),
        closeTo(114, 1e-9),
      );
    });

    test('a cap stops the upside dead', () {
      const CapitalProtectedNote note = CapitalProtectedNote(
        participation: 1,
        capLevel: 130,
      );
      expect(note.redemptionAtExpiry(130, initialSpot: 100), closeTo(130, 1e-9));
      expect(note.redemptionAtExpiry(200, initialSpot: 100), closeTo(130, 1e-9));
    });

    test('partial protection can lose money at maturity', () {
      const CapitalProtectedNote note = CapitalProtectedNote(
        protectionLevel: 0.9,
      );
      expect(note.redemptionAtExpiry(10, initialSpot: 100), closeTo(90, 1e-9));
      expect(note.value(market).maxLossDescription, contains('10%'));
    });
  });

  group('ReverseConvertible', () {
    test('the parts add up to the whole, and one of them is sold', () {
      const ReverseConvertible note = ReverseConvertible();
      final StructuredValuation v = note.value(market);

      double sum = 0;
      for (final ProductComponent c in v.components) {
        sum += c.value;
      }
      expect(v.fairValue, closeTo(sum, 1e-12));
      expect(v.components.where((ProductComponent c) => c.isSold).length, 1);
    });

    test('the sold put is priced as a plain Black-Scholes put', () {
      const ReverseConvertible note = ReverseConvertible(strikeRatio: 1);
      final StructuredValuation v = note.value(market);

      final double expected = -(100 / 100) *
          bsmQuote(
            OptionType.put,
            const BsmInputs(
              spot: 100,
              strike: 100,
              rate: 0.03,
              volatility: 0.22,
              timeToExpiry: 1,
              dividendYield: 0.02,
            ),
          ).price;

      expect(v.components.last.value, closeTo(expected, 1e-9));
    });

    test('gains are capped at the coupon however far the underlying rises', () {
      const ReverseConvertible note = ReverseConvertible(couponRate: 0.12);
      // The defining asymmetry, and the reason the coupon is not generosity.
      expect(note.redemptionAtExpiry(100, initialSpot: 100), closeTo(112, 1e-9));
      expect(note.redemptionAtExpiry(200, initialSpot: 100), closeTo(112, 1e-9));
      expect(
        note.redemptionAtExpiry(1000, initialSpot: 100),
        closeTo(112, 1e-9),
      );
    });

    test('losses are not capped', () {
      const ReverseConvertible note = ReverseConvertible(couponRate: 0.12);
      // Repaid in shares worth a quarter of the cash that bought them.
      expect(note.redemptionAtExpiry(25, initialSpot: 100), closeTo(37, 1e-9));
      // A total collapse leaves only the coupon.
      expect(
        note.redemptionAtExpiry(0.0001, initialSpot: 100),
        closeTo(12, 1e-3),
      );
    });

    test('a lower strike means a cheaper sold put and a lower value', () {
      const ReverseConvertible atMoney = ReverseConvertible();
      const ReverseConvertible lower = ReverseConvertible(strikeRatio: 0.8);
      // A put struck lower is worth less, so less is being received for it —
      // but the bond and coupon legs are unchanged, so the product is worth
      // MORE to the buyer.
      expect(
        lower.value(market).fairValue,
        greaterThan(atMoney.value(market).fairValue),
      );
    });
  });

  group('BarrierReverseConvertible', () {
    test('is worth more than the plain version at the same coupon', () {
      // The sold option is a down-and-in put rather than a full put, so the
      // buyer has given away less. At an equal coupon the barrier version is
      // therefore the better deal — which is why issuers pay a LOWER coupon
      // on it.
      const ReverseConvertible plain = ReverseConvertible(couponRate: 0.08);
      const BarrierReverseConvertible barrier = BarrierReverseConvertible(
        couponRate: 0.08,
      );

      expect(
        barrier.value(market).fairValue,
        greaterThan(plain.value(market).fairValue),
      );
    });

    test('the sold leg is exactly a down-and-in put', () {
      const BarrierReverseConvertible note = BarrierReverseConvertible(
        barrierRatio: 0.65,
      );
      final StructuredValuation v = note.value(market);

      final double expected = -barrierPrice(
        const BarrierSpec(
          type: OptionType.put,
          direction: BarrierDirection.down,
          style: BarrierStyle.knockIn,
          barrier: 65,
        ),
        const BsmInputs(
          spot: 100,
          strike: 100,
          rate: 0.03,
          volatility: 0.22,
          timeToExpiry: 1,
          dividendYield: 0.02,
        ),
      );

      expect(v.components.last.value, closeTo(expected, 1e-9));
    });

    test('a barrier that is never touched repays in full', () {
      const BarrierReverseConvertible note = BarrierReverseConvertible(
        couponRate: 0.08,
        barrierRatio: 0.65,
      );
      // Fell to 70 — below the strike, but never through the barrier.
      expect(
        note.redemptionAtExpiry(70, initialSpot: 100, lowestSpotReached: 70),
        closeTo(108, 1e-9),
      );
    });

    /// The misreading this product invites: people treat the barrier as the
    /// floor. It is not. Once breached, the loss is measured from the STRIKE.
    test('a breached barrier means loss from the STRIKE, not from the barrier', () {
      const BarrierReverseConvertible note = BarrierReverseConvertible(
        couponRate: 0.08,
        barrierRatio: 0.65,
        strikeRatio: 1,
      );
      // Dipped to 60 (through the barrier) and finished at 64.
      final double redemption = note.redemptionAtExpiry(
        64,
        initialSpot: 100,
        lowestSpotReached: 60,
      );
      // Shares worth 64, not 65 — plus the coupon. If the barrier were a
      // floor this would be 100 + 8.
      expect(redemption, closeTo(72, 1e-9));
      expect(redemption, lessThan(100));
    });

    test('a breach followed by a recovery above the strike still repays in full', () {
      const BarrierReverseConvertible note = BarrierReverseConvertible(
        couponRate: 0.08,
        barrierRatio: 0.65,
      );
      expect(
        note.redemptionAtExpiry(105, initialSpot: 100, lowestSpotReached: 50),
        closeTo(108, 1e-9),
      );
    });

    test('a lower barrier is safer, so the product is worth more', () {
      double valueAt(double ratio) => BarrierReverseConvertible(
        barrierRatio: ratio,
      ).value(market).fairValue;

      expect(valueAt(0.5), greaterThan(valueAt(0.8)));
    });
  });

  group('DiscountCertificate', () {
    test('is a covered call: long the underlying, short a call at the cap', () {
      const DiscountCertificate note = DiscountCertificate(capRatio: 1.05);
      final StructuredValuation v = note.value(market);

      expect(v.components.length, 2);
      expect(v.components.first.isSold, isFalse);
      expect(v.components.last.isSold, isTrue);

      final double expectedCall = -bsmQuote(
        OptionType.call,
        const BsmInputs(
          spot: 100,
          strike: 105,
          rate: 0.03,
          volatility: 0.22,
          timeToExpiry: 1,
          dividendYield: 0.02,
        ),
      ).price;
      expect(v.components.last.value, closeTo(expectedCall, 1e-9));
    });

    test('sells at a discount to the underlying', () {
      const DiscountCertificate note = DiscountCertificate();
      expect(note.value(market).fairValue, lessThan(100));
    });

    test('the upside stops at the cap and the downside does not stop', () {
      const DiscountCertificate note = DiscountCertificate(capRatio: 1.05);
      expect(note.redemptionAtExpiry(105, initialSpot: 100), closeTo(105, 1e-9));
      expect(note.redemptionAtExpiry(500, initialSpot: 100), closeTo(105, 1e-9));
      expect(note.redemptionAtExpiry(40, initialSpot: 100), closeTo(40, 1e-9));
      expect(note.redemptionAtExpiry(0, initialSpot: 100), closeTo(0, 1e-9));
    });

    test('a higher cap gives up less upside, so costs more', () {
      double valueAt(double cap) =>
          DiscountCertificate(capRatio: cap).value(market).fairValue;
      expect(valueAt(1.3), greaterThan(valueAt(1.05)));
    });

    test('dividends going to the issuer reduce what the buyer holds', () {
      const DiscountCertificate note = DiscountCertificate();
      final double withDividends = note.value(market).fairValue;
      final double without = note
          .value(market.copyWith(dividendYield: 0))
          .fairValue;
      expect(withDividends, lessThan(without));
    });
  });

  group('the honesty the wrapper hides', () {
    /// The number brochures do not print. Buying at par a bundle worth less
    /// than par is not a scandal — issuers have costs — but a buyer who
    /// cannot see the gap cannot judge the deal.
    test('every product sold at par carries a visible issue margin', () {
      final List<StructuredProduct> products = <StructuredProduct>[
        const CapitalProtectedNote(),
        const ReverseConvertible(),
        const BarrierReverseConvertible(),
        const DiscountCertificate(),
      ];

      for (final StructuredProduct p in products) {
        final StructuredValuation v = p.value(market);
        expect(v.issueMargin, closeTo(v.notional - v.fairValue, 1e-12));
        expect(
          v.issueMarginPercent,
          closeTo(100 * v.issueMargin / v.notional, 1e-12),
        );
      }
    });

    test('a note sold at par is worth less than par on day one', () {
      // The classic retail note: five years, full protection, 70% of the
      // upside, on an underlying that pays dividends the holder never sees.
      const CapitalProtectedNote note = CapitalProtectedNote(
        maturityYears: 5,
        protectionLevel: 1,
        participation: 0.7,
      );
      final StructuredValuation v = note.value(market);

      expect(v.fairValue, lessThan(100));
      expect(v.issueMargin, greaterThan(0));
    });

    test('every product states its worst case in words', () {
      for (final StructuredProduct p in <StructuredProduct>[
        const CapitalProtectedNote(),
        const ReverseConvertible(),
        const BarrierReverseConvertible(),
        const DiscountCertificate(),
      ]) {
        final String worstCase = p.value(market).maxLossDescription;
        expect(worstCase, isNotEmpty);
        expect(worstCase.length, greaterThan(40));
        expect(p.label, isNotEmpty);
        expect(p.purpose, isNotEmpty);
      }
    });

    test('the capital-protected note names its issuer risk', () {
      // "Capital protected" is a promise by a bank, not a law of nature.
      expect(
        const CapitalProtectedNote().value(market).maxLossDescription,
        contains('issuer'),
      );
    });

    test('every component explains itself', () {
      for (final StructuredProduct p in <StructuredProduct>[
        const CapitalProtectedNote(capLevel: 130),
        const ReverseConvertible(),
        const BarrierReverseConvertible(),
        const DiscountCertificate(),
      ]) {
        for (final ProductComponent c in p.value(market).components) {
          expect(c.name, isNotEmpty, reason: p.label);
          expect(c.explanation.length, greaterThan(20), reason: p.label);
        }
      }
    });
  });
}
