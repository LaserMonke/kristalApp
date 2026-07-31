/// Structured products, priced as compositions of the pieces already built
/// (Phase 8).
///
/// Pure Dart with NO Flutter imports (CLAUDE.md architecture rule).
///
/// WHAT A STRUCTURED PRODUCT IS. A single certificate, sold with a headline
/// like "100% capital protection with 70% of any rise" or "12% coupon", that
/// is really a BUNDLE: a bond plus one or more options, wrapped up and sold
/// as one thing. Nothing in this file invents new mathematics. Every product
/// here is decomposed into parts that `black_scholes.dart` and `barrier.dart`
/// already price, and the decomposition IS the teaching content — once a
/// learner can see the bond and the option inside the wrapper, the headline
/// stops being magic and becomes arithmetic.
///
/// WHY THIS MATTERS FOR HONESTY (CLAUDE.md rules 2, 3 and 4). Structured
/// products are the retail instruments most often sold on a number that hides
/// their economics. Four things the brochure tends to underplay, and which
/// [StructuredValuation] therefore makes explicit:
///
///   1. THE MARGIN. A note sold at 100 is usually worth less than 100 the
///      moment it is issued. The gap is the issuer's fees and profit, paid
///      by the buyer on day one. [StructuredValuation.issueMargin] measures
///      it, and it is typically several percent.
///   2. THE FORGONE DIVIDENDS. Upside participation is on the PRICE, not on
///      the total return. Dividends stay with the issuer, and over a
///      multi-year note they are a large part of how the product is funded.
///   3. THE PROTECTION IS ONLY AT MATURITY. "Capital protected" describes
///      what happens on one date. Sell early and the price is whatever the
///      market says, which can be well below par.
///   4. THE ISSUER CAN FAIL. Every one of these is an unsecured promise by a
///      bank. The bond leg is only worth what the issuer's credit is worth,
///      and the risk-free discounting used here deliberately IGNORES that —
///      so these values are upper bounds. Lehman Brothers issued
///      "capital-protected" notes.
///
/// ASSUMPTIONS. Everything from `black_scholes.dart`, plus: a single flat
/// risk-free rate used both to discount the bond and to price the options; no
/// credit spread and no default; no fees beyond the margin the valuation
/// reveals; and European exercise throughout.
library;

import 'dart:math' as math;

import 'barrier.dart';
import 'black_scholes.dart';

/// The market a structured product is valued in.
///
/// Carries a dividend yield, unlike the simpler environment the Phase 4
/// pricer uses, because forgone dividends are central to how these products
/// are funded rather than a detail.
class ProductMarket {
  const ProductMarket({
    required this.spot,
    required this.volatility,
    required this.rate,
    this.dividendYield = 0,
  }) : assert(spot > 0, 'spot must be positive'),
       assert(volatility > 0, 'volatility must be positive');

  final double spot;
  final double volatility;
  final double rate;
  final double dividendYield;

  ProductMarket copyWith({
    double? spot,
    double? volatility,
    double? rate,
    double? dividendYield,
  }) => ProductMarket(
    spot: spot ?? this.spot,
    volatility: volatility ?? this.volatility,
    rate: rate ?? this.rate,
    dividendYield: dividendYield ?? this.dividendYield,
  );
}

/// One piece of a decomposed product.
class ProductComponent {
  const ProductComponent({
    required this.name,
    required this.value,
    required this.explanation,
  });

  final String name;

  /// Signed value per unit of notional: positive is something the holder
  /// owns, negative something they have sold. A negative component is where
  /// the headline coupon comes from, and where the risk comes from too.
  final double value;

  final String explanation;

  bool get isSold => value < 0;
}

/// What a product is worth, and what it is made of.
class StructuredValuation {
  const StructuredValuation({
    required this.notional,
    required this.components,
    required this.maxLossDescription,
  });

  /// The face amount the product is sold at, typically 100 or 1000.
  final double notional;

  final List<ProductComponent> components;

  /// Plain-language worst case. Never omitted, never softened — a product
  /// whose downside cannot be stated in a sentence has no business being
  /// taught as simple (CLAUDE.md rule 2).
  final String maxLossDescription;

  /// Model value today: simply the sum of the parts.
  double get fairValue => components.fold<double>(
    0,
    (double sum, ProductComponent c) => sum + c.value,
  );

  /// What the buyer pays over the model value when they buy at par.
  ///
  /// This is the number brochures do not print. It is not a criticism of any
  /// particular product — an issuer has costs and is entitled to a margin —
  /// but a buyer who cannot see it cannot judge whether the deal is fair.
  double get issueMargin => notional - fairValue;

  /// The margin as a percentage of the amount invested.
  double get issueMarginPercent =>
      notional == 0 ? 0 : 100 * issueMargin / notional;
}

/// A product that can be valued and whose payoff can be drawn.
sealed class StructuredProduct {
  const StructuredProduct({
    required this.notional,
    required this.maturityYears,
  }) : assert(notional > 0, 'notional must be positive'),
       assert(maturityYears > 0, 'maturity must be positive');

  final double notional;
  final double maturityYears;

  /// Short name for the UI.
  String get label;

  /// One sentence on what the product is trying to do for its buyer.
  String get purpose;

  /// The bundle, priced.
  StructuredValuation value(ProductMarket market);

  /// What the holder receives at maturity if the underlying finishes at
  /// [spotAtExpiry], per unit of notional.
  ///
  /// [lowestSpotReached] is the minimum the underlying touched over the life
  /// of the product; it matters only to products with a barrier, and defaults
  /// to [spotAtExpiry] (a path that only ever went up).
  double redemptionAtExpiry(
    double spotAtExpiry, {
    required double initialSpot,
    double? lowestSpotReached,
  });
}

/// CAPITAL-PROTECTED NOTE — a bond plus a call.
///
/// "Get your money back at maturity, plus a share of any rise." The buyer's
/// money mostly buys a zero-coupon bond that grows to the protected amount by
/// maturity; whatever is left over buys call options, and how many it buys
/// determines the participation rate.
///
/// The honest reading: the buyer has given up the dividends and the interest
/// their money would otherwise have earned, in exchange for a capped-cost bet
/// on the upside. In a low-rate world the bond costs nearly the whole
/// notional and there is little left for options, so participation collapses
/// — which is why these were common when rates were high and thin on the
/// ground when rates were near zero. The protection is real, and it is not
/// free.
class CapitalProtectedNote extends StructuredProduct {
  const CapitalProtectedNote({
    super.notional = 100,
    super.maturityYears = 5,
    this.protectionLevel = 1.0,
    this.participation = 0.7,
    this.capLevel,
  }) : assert(
         protectionLevel >= 0 && protectionLevel <= 1,
         'protection is a fraction of notional',
       ),
       assert(participation > 0, 'participation must be positive');

  /// Fraction of the notional returned at maturity whatever happens: 1.0 is
  /// "full capital protection", 0.9 is "90% protection" (up to 10% can be
  /// lost).
  final double protectionLevel;

  /// Share of the underlying's percentage rise that is passed on. 0.7 means
  /// a 20% rise pays 14%.
  final double participation;

  /// Optional ceiling on the underlying, above which no further upside is
  /// paid. Implemented as a SOLD call at that level, which is exactly what it
  /// is — and selling it is how a higher participation rate is funded.
  final double? capLevel;

  @override
  String get label => 'Capital-protected note';

  @override
  String get purpose =>
      'Returns a set fraction of your money at maturity whatever happens, '
      'plus a share of any rise in the underlying.';

  @override
  StructuredValuation value(ProductMarket market) {
    final double t = maturityYears;
    final double protectedAmount = notional * protectionLevel;
    // The bond: what it costs today to guarantee the protected amount at
    // maturity. Discounted at the risk-free rate, which flatters the product
    // — a real issuer's bond is worth less than this.
    final double bond = protectedAmount * _discount(market.rate, t);

    // Participation is bought as calls struck at today's level. One unit of
    // notional tracks notional/spot shares, so that a 10% rise pays 10% of
    // the notional before participation is applied.
    final double sharesPerNote = notional / market.spot;
    final double callValue =
        participation *
        sharesPerNote *
        bsmQuote(
          OptionType.call,
          _inputs(market, strike: market.spot, years: t),
        ).price;

    final List<ProductComponent> components = <ProductComponent>[
      ProductComponent(
        name: 'Zero-coupon bond',
        value: bond,
        explanation:
            'Grows to ${protectedAmount.toStringAsFixed(0)} by maturity. This '
            'is what the protection actually is: a promise from the issuer, '
            'worth what the issuer is worth.',
      ),
      ProductComponent(
        name:
            'Long call at ${market.spot.toStringAsFixed(0)} '
            '(${(participation * 100).toStringAsFixed(0)}% participation)',
        value: callValue,
        explanation:
            'The upside. Bought with whatever the bond did not consume, which '
            'is why participation falls when interest rates are low.',
      ),
    ];

    if (capLevel != null) {
      // Selling the upside above the cap raises cash, which funds a higher
      // participation rate below it. Shown as a negative component because
      // that is what it is: something the buyer has given away.
      final double soldCall =
          -participation *
          sharesPerNote *
          bsmQuote(
            OptionType.call,
            _inputs(market, strike: capLevel!, years: t),
          ).price;
      components.add(
        ProductComponent(
          name: 'Short call at ${capLevel!.toStringAsFixed(0)} (the cap)',
          value: soldCall,
          explanation:
              'Upside above this level is sold away to pay for a higher '
              'participation rate below it. A rise beyond the cap earns the '
              'holder nothing further.',
        ),
      );
    }

    return StructuredValuation(
      notional: notional,
      components: components,
      maxLossDescription: protectionLevel >= 1
          ? 'At maturity you get your money back even if the underlying '
                'collapses. You can still lose in real terms: no dividends, no '
                'interest, and inflation over ${maturityYears.toStringAsFixed(0)} '
                'years. Sell early and you get the market price, which can be '
                'below par. If the issuer fails, the protection fails with it.'
          : 'Up to ${((1 - protectionLevel) * 100).toStringAsFixed(0)}% of your '
                'money can be lost at maturity, plus dividends and interest '
                'forgone. If the issuer fails you can lose everything.',
    );
  }

  @override
  double redemptionAtExpiry(
    double spotAtExpiry, {
    required double initialSpot,
    double? lowestSpotReached,
  }) {
    final double capped = capLevel == null
        ? spotAtExpiry
        : (spotAtExpiry < capLevel! ? spotAtExpiry : capLevel!);
    final double rise = capped > initialSpot ? capped - initialSpot : 0;
    final double upside = participation * notional * rise / initialSpot;
    return notional * protectionLevel + upside;
  }
}

/// REVERSE CONVERTIBLE — a bond plus a SOLD put.
///
/// "A 12% coupon, paid whatever happens." The coupon is high because the
/// buyer is not merely lending; they have also sold someone the right to hand
/// them the shares at today's price. If the underlying falls, that is what
/// happens: the notional comes back as shares worth less than the cash that
/// bought them.
///
/// The honest reading, and the reason this product deserves its reputation:
/// the buyer has a CAPPED gain (the coupon, and nothing more, however far the
/// underlying rises) and an UNCAPPED loss all the way down to zero. That is
/// the payoff shape of a short put, because that is what it is. A high coupon
/// is not generosity; it is the premium for insurance the buyer has written.
class ReverseConvertible extends StructuredProduct {
  const ReverseConvertible({
    super.notional = 100,
    super.maturityYears = 1,
    this.couponRate = 0.12,
    this.strikeRatio = 1.0,
  }) : assert(couponRate >= 0, 'coupon cannot be negative'),
       assert(strikeRatio > 0, 'strike ratio must be positive');

  /// Annual coupon as a fraction of notional, paid regardless of what the
  /// underlying does.
  final double couponRate;

  /// Strike as a multiple of the initial spot. 1.0 means the buyer takes
  /// delivery if the underlying finishes anywhere below its starting level.
  final double strikeRatio;

  @override
  String get label => 'Reverse convertible';

  @override
  String get purpose =>
      'Pays a high fixed coupon. In exchange, if the underlying falls you are '
      'repaid in shares instead of cash.';

  @override
  StructuredValuation value(ProductMarket market) {
    final double t = maturityYears;
    final double strike = market.spot * strikeRatio;
    final double discount = _discount(market.rate, t);

    final double redemption = notional * discount;
    final double coupon = notional * couponRate * t * discount;
    final double sharesPerNote = notional / strike;
    final double soldPut =
        -sharesPerNote *
        bsmQuote(OptionType.put, _inputs(market, strike: strike, years: t)).price;

    return StructuredValuation(
      notional: notional,
      components: <ProductComponent>[
        ProductComponent(
          name: 'Zero-coupon bond',
          value: redemption,
          explanation:
              'The notional, repaid at maturity — in cash if the underlying '
              'holds up, otherwise in shares.',
        ),
        ProductComponent(
          name: 'Coupon',
          value: coupon,
          explanation:
              '${(couponRate * 100).toStringAsFixed(1)}% a year, paid whatever '
              'happens. This is the whole of the upside: the underlying '
              'doubling would not add a penny.',
        ),
        ProductComponent(
          name: 'Short put at ${strike.toStringAsFixed(0)}',
          value: soldPut,
          explanation:
              'Where the coupon comes from. The buyer has sold the right to '
              'be handed the shares at ${strike.toStringAsFixed(0)}, so a fall '
              'below that is theirs to absorb, all the way down.',
        ),
      ],
      maxLossDescription:
          'Gains are capped at the coupon, however far the underlying rises. '
          'Losses are not capped: if the underlying finishes at zero you are '
          'left with worthless shares and only the coupon, losing close to '
          '100% of your money.',
    );
  }

  @override
  double redemptionAtExpiry(
    double spotAtExpiry, {
    required double initialSpot,
    double? lowestSpotReached,
  }) {
    final double strike = initialSpot * strikeRatio;
    final double coupon = notional * couponRate * maturityYears;
    if (spotAtExpiry >= strike) return notional + coupon;
    // Repaid in shares: notional/strike shares, each now worth spotAtExpiry.
    return notional * spotAtExpiry / strike + coupon;
  }
}

/// BARRIER REVERSE CONVERTIBLE — a bond plus a sold DOWN-AND-IN put.
///
/// The most-sold structured product in several European markets, and the one
/// whose risk is most easily misread. It looks like a reverse convertible
/// with a safety net: the shares are only delivered if the underlying ever
/// falls through a barrier well below today's price. Most of the time it does
/// not, the coupon is paid, and the product looks like a very good bond.
///
/// The honest reading: the barrier does not reduce the loss, it only changes
/// how often the loss happens. When the barrier is breached the sold put wakes
/// up in full, and the buyer absorbs the fall from the STRIKE — not from the
/// barrier. So the outcome distribution is "a good coupon, most of the time"
/// punctuated by an occasional large loss, which is precisely the shape that
/// looks safest for longest and flatters a short track record.
class BarrierReverseConvertible extends StructuredProduct {
  const BarrierReverseConvertible({
    super.notional = 100,
    super.maturityYears = 1,
    this.couponRate = 0.08,
    this.strikeRatio = 1.0,
    this.barrierRatio = 0.65,
  }) : assert(couponRate >= 0, 'coupon cannot be negative'),
       assert(
         barrierRatio > 0 && barrierRatio < 1,
         'the barrier sits below the initial level',
       );

  final double couponRate;
  final double strikeRatio;

  /// Barrier as a multiple of the initial spot. 0.65 means the underlying
  /// must fall 35% at some point before the downside is triggered at all.
  final double barrierRatio;

  @override
  String get label => 'Barrier reverse convertible';

  @override
  String get purpose =>
      'Pays a fixed coupon, and returns your money in full unless the '
      'underlying ever falls through a barrier well below today\'s price.';

  @override
  StructuredValuation value(ProductMarket market) {
    final double t = maturityYears;
    final double strike = market.spot * strikeRatio;
    final double barrier = market.spot * barrierRatio;
    final double discount = _discount(market.rate, t);

    final double redemption = notional * discount;
    final double coupon = notional * couponRate * t * discount;
    final double sharesPerNote = notional / strike;

    // A down-and-in put: worthless unless the barrier is touched, a full put
    // from the moment it is. Cheaper than the plain put in ReverseConvertible,
    // which is exactly why this product's coupon is lower.
    final double soldPut =
        -sharesPerNote *
        barrierPrice(
          BarrierSpec(
            type: OptionType.put,
            direction: BarrierDirection.down,
            style: BarrierStyle.knockIn,
            barrier: barrier,
          ),
          _inputs(market, strike: strike, years: t),
        );

    return StructuredValuation(
      notional: notional,
      components: <ProductComponent>[
        ProductComponent(
          name: 'Zero-coupon bond',
          value: redemption,
          explanation: 'The notional, repaid at maturity.',
        ),
        ProductComponent(
          name: 'Coupon',
          value: coupon,
          explanation:
              '${(couponRate * 100).toStringAsFixed(1)}% a year. Lower than a '
              'plain reverse convertible would pay, because the put being sold '
              'is a cheaper one.',
        ),
        ProductComponent(
          name:
              'Short down-and-in put, strike ${strike.toStringAsFixed(0)}, '
              'barrier ${barrier.toStringAsFixed(0)}',
          value: soldPut,
          explanation:
              'Dormant unless the underlying touches '
              '${barrier.toStringAsFixed(0)}. If it does, it becomes an '
              'ordinary sold put struck at ${strike.toStringAsFixed(0)} — and '
              'the loss is measured from the strike, not from the barrier.',
        ),
      ],
      maxLossDescription:
          'While the barrier holds, you get the coupon and your money back. If '
          'it breaks, you absorb the entire fall from '
          '${strike.toStringAsFixed(0)} downwards — a barrier at '
          '${(barrierRatio * 100).toStringAsFixed(0)}% breached means a loss of '
          'at least ${((1 - barrierRatio) * 100).toStringAsFixed(0)}% of the '
          'underlying, not a loss capped at it. Gains never exceed the coupon.',
    );
  }

  @override
  double redemptionAtExpiry(
    double spotAtExpiry, {
    required double initialSpot,
    double? lowestSpotReached,
  }) {
    final double strike = initialSpot * strikeRatio;
    final double barrier = initialSpot * barrierRatio;
    final double coupon = notional * couponRate * maturityYears;
    final double lowest = lowestSpotReached ?? spotAtExpiry;

    // Untouched barrier, or recovered above the strike: full repayment.
    if (lowest > barrier || spotAtExpiry >= strike) {
      return notional + coupon;
    }
    return notional * spotAtExpiry / strike + coupon;
  }
}

/// DISCOUNT CERTIFICATE — the underlying, bought cheap, with the upside sold.
///
/// Buy the share at a discount to its market price; in exchange, any rise
/// above a cap belongs to someone else. It is a covered call in a wrapper,
/// and the discount is simply the call premium paid up front.
///
/// The honest reading: the discount is a cushion, not protection. It absorbs
/// the first few percent of a fall and nothing more — below that the holder
/// takes the full decline, exactly as a shareholder would, while having given
/// away the recovery above the cap.
class DiscountCertificate extends StructuredProduct {
  const DiscountCertificate({
    super.notional = 100,
    super.maturityYears = 1,
    this.capRatio = 1.05,
  }) : assert(capRatio > 0, 'cap must be positive');

  /// Cap as a multiple of the initial spot.
  final double capRatio;

  @override
  String get label => 'Discount certificate';

  @override
  String get purpose =>
      'Buys the underlying at a discount to its price, in exchange for giving '
      'up any rise above a cap.';

  @override
  StructuredValuation value(ProductMarket market) {
    final double t = maturityYears;
    final double cap = market.spot * capRatio;
    final double sharesPerNote = notional / market.spot;

    // Long the underlying, short a call at the cap. Dividends over the life
    // of the note go to the issuer, which is why the underlying leg is
    // discounted by the dividend yield.
    final double underlying =
        sharesPerNote * market.spot * _discount(market.dividendYield, t);
    final double soldCall =
        -sharesPerNote *
        bsmQuote(OptionType.call, _inputs(market, strike: cap, years: t)).price;

    return StructuredValuation(
      notional: notional,
      components: <ProductComponent>[
        ProductComponent(
          name: 'The underlying',
          value: underlying,
          explanation: market.dividendYield > 0
              ? 'Worth less than the share price because the dividends over '
                    'the next ${t.toStringAsFixed(0)} year(s) go to the issuer, '
                    'not to you.'
              : 'A straight holding in the underlying.',
        ),
        ProductComponent(
          name: 'Short call at ${cap.toStringAsFixed(0)} (the cap)',
          value: soldCall,
          explanation:
              'The discount, in exchange for the upside. Any rise above '
              '${cap.toStringAsFixed(0)} belongs to the issuer.',
        ),
      ],
      maxLossDescription:
          'The discount cushions the first part of a fall and no more. Below '
          'that you take the full decline, down to a total loss if the '
          'underlying reaches zero — while any recovery above '
          '${cap.toStringAsFixed(0)} is not yours.',
    );
  }

  @override
  double redemptionAtExpiry(
    double spotAtExpiry, {
    required double initialSpot,
    double? lowestSpotReached,
  }) {
    final double cap = initialSpot * capRatio;
    final double settled = spotAtExpiry < cap ? spotAtExpiry : cap;
    return notional * settled / initialSpot;
  }
}

/// Present value of 1 paid in [years] time at a continuously compounded
/// [rate].
///
/// Named rather than inlined because it appears in every product above and is
/// the single idea — money later is worth less than money now — that all of
/// them are built on. It is also where the credit assumption lives: [rate] is
/// risk-free here, so every bond leg is valued as if the issuer cannot fail.
double _discount(double rate, double years) => math.exp(-rate * years);

BsmInputs _inputs(
  ProductMarket market, {
  required double strike,
  required double years,
}) => BsmInputs(
  spot: market.spot,
  strike: strike,
  rate: market.rate,
  volatility: market.volatility,
  timeToExpiry: years,
  dividendYield: market.dividendYield,
);
